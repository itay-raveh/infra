import assert from 'node:assert/strict';
import { test } from 'node:test';
import { controller, usageCost } from '../clusters/shire/apps/quizmon-spending-guard/guard.mjs';

const config = { account: 'a'.repeat(32), zone: 'b'.repeat(32), namespace: 'c'.repeat(32), hostname: 'game.example.test', token: 'test-token', budget: 1 };
function fixture(spend = 0) {
  const state = { lease: { enabled: true, expiresAt: 600001 }, blocked: false, billingFails: false, renewalFails: false, mutations: [] };
  const request = async (url, options) => {
    const path = new URL(url).pathname;
    const method = options.method;
    const body = options.body ? JSON.parse(options.body) : undefined;
    if (method !== 'GET') state.mutations.push({ path, body });
    if (path.endsWith('/values/lease')) {
      if (method === 'GET') return Response.json(state.lease);
      if (state.renewalFails && body.enabled) return Response.json({}, { status: 503 });
      state.lease = body;
      return Response.json({ success: true, result: null });
    }
    if (path.endsWith('/billable-usage/info')) return Response.json({ success: true, result: { covered: true, subscriptions: [{}] } });
    if (path.endsWith('/billable-usage')) {
      if (state.billingFails) return Response.json({}, { status: 503 });
      return Response.json({ success: true, result: [{ BillingCurrency: 'USD', ChargeCategory: 'Usage', ContractedCost: spend }] });
    }
    if (path.endsWith('/entrypoint')) return Response.json({ success: true, result: { id: 'ruleset', rules: [{ id: 'rule', ref: 'quizmon_spending_shutdown', expression: '(http.host eq "game.example.test")', action: 'block', enabled: state.blocked }] } });
    if (path.endsWith('/rules/rule') && method === 'PATCH') {
      state.blocked = body.enabled;
      return Response.json({ success: true, result: {} });
    }
    throw new Error('Unexpected request');
  };
  return { state, guard: controller(config, request, () => 1) };
}

test('uses charge-period costs without summing cumulative cost repeatedly', () => {
  assert.equal(usageCost([
    { BillingCurrency: 'USD', ChargeCategory: 'Usage', ContractedCost: 0.25, CumulatedContractedCost: 0.25 },
    { BillingCurrency: 'USD', ChargeCategory: 'Usage', ContractedCost: 0.30, CumulatedContractedCost: 0.55 },
  ]), 0.55);
  assert.equal(usageCost([]), 0);
  for (const rows of [null, [{}], [{ BillingCurrency: 'EUR', ChargeCategory: 'Usage', ContractedCost: 1 }]]) assert.throws(() => usageCost(rows));
});
test('renews a short lease below budget and never modifies an inactive firewall rule', async () => {
  const { guard, state } = fixture(0.5);
  assert.deepEqual(await guard.check(), { state: 'active', usageUsd: 0.5 });
  assert.equal(state.lease.expiresAt, 600001);
  assert.equal(state.blocked, false);
  assert.equal(state.mutations.length, 1);
});
test('latches the shutdown at the exact threshold and blocks requests at the firewall', async () => {
  const { guard, state } = fixture(1);
  assert.equal((await guard.check()).state, 'paused');
  assert.equal(state.lease.enabled, false);
  assert.equal(state.blocked, true);
  await assert.rejects(guard.resume(), /Budget is exhausted/);
});
test('a manual shutdown stays latched even when billing reports zero', async () => {
  const { guard, state } = fixture();
  await guard.pause('manual');
  await guard.check();
  assert.equal(state.lease.enabled, false);
  assert.equal(state.blocked, true);
  await guard.resume();
  assert.equal(state.lease.enabled, true);
  assert.equal(state.blocked, false);
});
test('a billing failure attempts both shutdown mechanisms and returns an error', async () => {
  const { guard, state } = fixture();
  state.billingFails = true;
  await assert.rejects(guard.check());
  assert.equal(state.lease.enabled, false);
  assert.equal(state.blocked, true);
});
test('does not bypass a firewall rule enabled by an operator', async () => {
  const { guard, state } = fixture();
  state.blocked = true;
  await guard.check();
  assert.equal(state.lease.enabled, false);
  assert.equal(state.blocked, true);
});
test('restores both shutdown mechanisms when permission renewal fails during resume', async () => {
  const { guard, state } = fixture();
  await guard.pause('manual');
  state.renewalFails = true;
  await assert.rejects(guard.resume());
  assert.equal(state.lease.enabled, false);
  assert.equal(state.blocked, true);
});
