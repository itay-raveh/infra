import privacy from "./privacy.html";
import ads from "./ads.txt";

export default {
  fetch(request) {
    const path = new URL(request.url).pathname;
    const isPrivacy = ["/privacy", "/privacy/", "/privacy.html"].includes(path);
    if (!isPrivacy && path !== "/ads.txt") {
      return new Response(null, { status: 404 });
    }
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response(null, {
        status: 405,
        headers: { Allow: "GET, HEAD" },
      });
    }
    return new Response(
      request.method === "HEAD" ? null : isPrivacy ? privacy : ads,
      {
        headers: {
          "Content-Type": isPrivacy
            ? "text/html; charset=utf-8"
            : "text/plain; charset=utf-8",
        },
      },
    );
  },
};
