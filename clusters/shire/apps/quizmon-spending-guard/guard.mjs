import { pathToFileURL } from 'node:url';
import { realpathSync } from 'node:fs';

export function usageCost(rows) {
  if (!Array.isArray(rows)) throw new Error('Invalid billing response');
  return rows.reduce((total, row) => {
    if (row.BillingCurrency !== 'USD' || row.ChargeCategory !== 'Usage' ||
        typeof row.ContractedCost !== 'number' || !Number.isFinite(row.ContractedCost) ||
        row.ContractedCost < 0) throw new Error('Unexpected billing record');
    return total + row.ContractedCost;
  }, 0);
}

export function configuration(env) {
  const required = name => {
    if (!env[name]) throw new Error(`Missing ${name}`);
    return env[name];
  };
  const hex = name => {
    const value = required(name);
    if (!/^[a-f0-9]{32}$/.test(value)) throw new Error(`Invalid ${name}`);
    return value;
  };
  const hostname = required('QUIZMON_HOSTNAME');
  if (!/^[a-z0-9.-]+$/.test(hostname)) throw new Error('Invalid hostname');
  const budget = Number(required('BUDGET_USD'));
  if (!Number.isFinite(budget) || budget <= 0) throw new Error('Invalid budget');
  return {
    account: hex('CLOUDFLARE_ACCOUNT_ID'), zone: hex('CLOUDFLARE_ZONE_ID'),
    namespace: hex('SPENDING_KV_NAMESPACE_ID'), token: required('CLOUDFLARE_API_TOKEN'),
    hostname, budget,
  };
}

export function controller(config, request = fetch, now = Date.now) {
  const base = 'https://api.cloudflare.com/client/v4';
  const leasePath = `/accounts/${config.account}/storage/kv/namespaces/${config.namespace}/values/lease`;
  const entrypoint = `/zones/${config.zone}/rulesets/phases/http_request_firewall_custom/entrypoint`;
  const ref = 'quizmon_spending_shutdown';
  const expression = `(http.host eq "${config.hostname}")`;
  async function raw(path, method = 'GET', body) {
    const response = await request(base + path, {
      method,
      headers: { Authorization: `Bearer ${config.token}`, 'Content-Type': 'application/json' },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      signal: AbortSignal.timeout(10_000), redirect: 'error',
    });
    if (!response.ok) {
      await response.body?.cancel();
      throw Object.assign(new Error(`Cloudflare ${method} failed (${response.status})`), { status: response.status });
    }
    const payload = await response.json();
    return payload;
  }
  async function api(path, method = 'GET', body) {
    const payload = await raw(path, method, body);
    if (payload.success !== true) throw new Error('Cloudflare request was rejected');
    return payload.result;
  }
  async function rule() {
    const ruleset = await api(entrypoint);
    const matches = ruleset.rules?.filter(item => (item.ref === ref || item.description === 'Quizmon spending shutdown')) ?? [];
    if (matches.length !== 1 || matches[0].expression !== expression || matches[0].action !== 'block')
      throw new Error('Shutdown firewall rule is missing or changed');
    return { ruleset, target: matches[0] };
  }
  async function firewall(enabled) {
    const { ruleset, target } = await rule();
    if (target.enabled === enabled) return;
    await api(`/zones/${config.zone}/rulesets/${ruleset.id}/rules/${target.id}`, 'PATCH', {
      action: 'block', expression, ref: target.ref, description: 'Quizmon spending shutdown', enabled,
    });
  }
  const lease = value => api(leasePath, 'PUT', value);
  async function cost() {
    const info = await api(`/accounts/${config.account}/billable-usage/info`);
    if (info.covered !== true || !Array.isArray(info.subscriptions) || !info.subscriptions.length)
      throw new Error('Account billing coverage is unavailable');
    return usageCost(await api(`/accounts/${config.account}/billable-usage`));
  }
  async function pause(reason) {
    const results = await Promise.allSettled([
      lease({ enabled: false, expiresAt: 0, reason, checkedAt: now() }),
      firewall(true),
    ]);
    if (results.some(result => result.status === 'rejected'))
      throw new Error('Shutdown only partially applied. Check KV and firewall.');
    return { state: 'paused', reason };
  }
  async function check() {
    try {
      const [current, spend] = await Promise.all([raw(leasePath), cost()]);
      if (current.enabled === false) return await pause('latched');
      if (current.enabled !== true || typeof current.expiresAt !== 'number')
        throw new Error('Spending control is uninitialized');
      if (spend >= config.budget) return await pause('budget');
      const { target } = await rule();
      if (target.enabled !== false) return await pause('firewall-already-paused');
      await lease({ enabled: true, expiresAt: now() + 10 * 60_000, checkedAt: now(), usageUsd: spend });
      return { state: 'active', usageUsd: spend };
    } catch (error) {
      await pause('monitor-error');
      throw error;
    }
  }
  async function resume() {
    const spend = await cost();
    if (spend >= config.budget) throw new Error('Budget is exhausted. Refusing to resume.');
    try {
      await firewall(false);
      await lease({ enabled: true, expiresAt: now() + 10 * 60_000, checkedAt: now(), usageUsd: spend });
    } catch (error) {
      await pause('resume-error');
      throw error;
    }
    return { state: 'active', usageUsd: spend };
  }
  async function setup() {
    let ruleset;
    try { ruleset = await api(entrypoint); }
    catch (error) {
      if (error.status !== 404) throw error;
    }
    const newRule = { ref, expression, action: 'block', description: 'Quizmon spending shutdown', enabled: false };
    if (!ruleset) await api(entrypoint, 'PUT', {
      name: 'Zone custom firewall rules', kind: 'zone', phase: 'http_request_firewall_custom', rules: [newRule],
    });
    else if (!ruleset.rules?.some(item => (item.ref === ref || item.description === 'Quizmon spending shutdown')))
      await api(`/zones/${config.zone}/rulesets/${ruleset.id}/rules`, 'POST', newRule);
    await rule();
    return { state: 'configured' };
  }
  return { check, pause, resume, setup };
}

if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
  try {
    const guard = controller(configuration(process.env));
    const mode = process.argv[2] ?? 'check';
    if (!['check', 'pause', 'resume', 'setup'].includes(mode)) throw new Error('Unknown mode');
    console.log(JSON.stringify(await guard[mode]('manual')));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
