// Independent cloud clock for the GitHub scanner. The GitHub cron remains a
// second trigger; neither trigger depends on a Windows machine being awake.
const REPO = 'datle90745/tgdd-khuyen-mai';
const WORKFLOW = 'scan-tgdd.yml';
const MAX_AGE_MS = 90 * 60 * 1000;
const MAX_PUBLIC_AGE_MS = 3 * 60 * 60 * 1000;
const PAGE_BUILD_GRACE_MS = 15 * 60 * 1000;
const ACTIVE = new Set(['queued', 'in_progress', 'waiting', 'pending', 'requested']);

export function latestAgeMs(source, now = Date.now()) {
  if (typeof source !== 'string') return Infinity;
  const start = source.indexOf('{');
  const end = source.lastIndexOf('}');
  if (start < 0 || end <= start) return Infinity;
  try {
    const latest = JSON.parse(source.slice(start, end + 1));
    const at = Date.parse(latest.scanned_at);
    if (!Number.isFinite(at) || !Array.isArray(latest.rows) || latest.rows.length < 1) return Infinity;
    const age = now - at;
    return age >= -60_000 ? age : Infinity;
  } catch {
    return Infinity;
  }
}

export async function checkScanner(env, request = fetch, now = Date.now(), dryRun = false) {
  if (!env.GH_DISPATCH_TOKEN) throw new Error('GH_DISPATCH_TOKEN is missing');
  const sourceUrl = `https://raw.githubusercontent.com/${REPO}/main/data/latest.js?watchdog=${now}`;
  const latestResponse = await request(sourceUrl, {headers: {'Cache-Control': 'no-cache'}});
  if (!latestResponse.ok) throw new Error(`Latest data HTTP ${latestResponse.status}`);
  const ageMs = latestAgeMs(await latestResponse.text(), now);
  const ageMinutes = Number.isFinite(ageMs) ? Math.floor(ageMs / 60_000) : null;
  const headers = {
    Authorization: `Bearer ${env.GH_DISPATCH_TOKEN}`,
    Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'tgdd-cloud-watchdog'
  };
  if (ageMs < MAX_AGE_MS) {
    // A new commit is not the same as a new public page. Repair a stuck Pages
    // build without repeating a costly retail scan or presenting old prices.
    const pageUrl = `https://datle90745.github.io/tgdd-khuyen-mai/data/latest.js?watchdog=${now}`;
    const pageResponse = await request(pageUrl, {headers: {'Cache-Control': 'no-cache'}});
    const pageAge = pageResponse.ok ? latestAgeMs(await pageResponse.text(), now) : Infinity;
    const publishedAgeMinutes = Number.isFinite(pageAge) ? Math.floor(pageAge / 60_000) : null;
    if (pageAge < MAX_PUBLIC_AGE_MS) return {state: 'fresh', ageMinutes, publishedAgeMinutes};
    const pagesApi = `https://api.github.com/repos/${REPO}/pages/builds`;
    const buildResponse = await request(`${pagesApi}/latest`, {headers});
    if (!buildResponse.ok) throw new Error(`Pages build HTTP ${buildResponse.status}`);
    const build = await buildResponse.json();
    const buildAge = now - Date.parse(build.created_at);
    if (build.status === 'building' || build.status === 'queued' ||
        (Number.isFinite(buildAge) && buildAge >= 0 && buildAge < PAGE_BUILD_GRACE_MS)) {
      return {state: 'pages_building', ageMinutes, publishedAgeMinutes};
    }
    if (dryRun) return {state: 'would_rebuild', ageMinutes, publishedAgeMinutes};
    const rebuild = await request(pagesApi, {method: 'POST', headers});
    if (rebuild.status !== 201 && rebuild.status !== 202) {
      throw new Error(`Pages rebuild HTTP ${rebuild.status}`);
    }
    return {state: 'pages_rebuild_requested', ageMinutes, publishedAgeMinutes};
  }

  const api = `https://api.github.com/repos/${REPO}/actions/workflows/${WORKFLOW}`;
  const runsResponse = await request(`${api}/runs?per_page=30`, {headers});
  if (!runsResponse.ok) throw new Error(`GitHub runs HTTP ${runsResponse.status}`);
  const runs = (await runsResponse.json()).workflow_runs;
  if (!Array.isArray(runs)) throw new Error('GitHub runs response is invalid');
  if (runs.some(run => ACTIVE.has(run.status))) return {state: 'running', ageMinutes};
  if (dryRun) return {state: 'would_dispatch', ageMinutes};

  const dispatchResponse = await request(`${api}/dispatches`, {
    method: 'POST', headers: {...headers, 'Content-Type': 'application/json'},
    body: JSON.stringify({ref: 'main'})
  });
  if (dispatchResponse.status !== 204) throw new Error(`GitHub dispatch HTTP ${dispatchResponse.status}`);
  return {state: 'dispatched', ageMinutes};
}

export default {
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(checkScanner(env).then(result => {
      console.log(`watchdog ${result.state}; latest_age_minutes=${result.ageMinutes}; ` +
        `published_age_minutes=${result.publishedAgeMinutes ?? 'unknown'}`);
    }).catch(error => {
      console.error(`watchdog error: ${error.message}`);
      throw error;
    }));
  },
  async fetch(request, env) {
    if (new URL(request.url).pathname !== '/health' || request.method !== 'GET') {
      return new Response('Not found', {status: 404});
    }
    try {
      const result = await checkScanner(env, fetch, Date.now(), true);
      return Response.json(result, {headers: {'Cache-Control': 'no-store'}});
    } catch (error) {
      return Response.json({state: 'error', message: error.message}, {status: 503,
        headers: {'Cache-Control': 'no-store'}});
    }
  }
};
