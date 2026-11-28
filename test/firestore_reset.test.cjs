const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { test } = require('node:test');

test('authenticated client resets only its own farm and cannot replay old batches', async () => {
  const { GCLOUD_PROJECT: project, FIREBASE_AUTH_EMULATOR_HOST: auth, FIRESTORE_EMULATOR_HOST: store } = process.env;
  assert.ok(project?.startsWith('demo-') && auth && store, 'Use Firebase emulators with a demo project.');
  const database = `projects/${project}/databases/(default)/documents`;
  const endpoint = `http://${store}/v1/${database}`;
  const signup = async () => {
    const response = await fetch(`http://${auth}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: `${randomUUID()}@example.com`, password: 'fixture-password', returnSecureToken: true }),
    });
    assert.ok(response.ok, await response.clone().text());
    return response.json();
  };
  const owner = await signup();
  const other = await signup();
  const account = `users/${owner.localId}`;
  const otherCrop = `users/${other.localId}/crops/other-crop`;
  const marker = `${account}/operations/farm_reset`;
  const archive = `${account}/history/archive`;
  const crop = `${account}/crops/current`;
  const orphan = `${account}/crops/missing/expenses/orphan`;
  const oldOrphan = `${archive}/crops_history/missing/expenses_history/orphan`;
  const marketProfile = `market_profiles/${owner.localId}`;
  const marketListing = `${marketProfile}/listings/rice`;
  const marketOrder = 'market_orders/reset-fixture';
  const fields = (data) => Object.fromEntries(Object.entries(data).map(([key, value]) => [
    key, value === null ? { nullValue: null } : { stringValue: value },
  ]));
  const request = (path, token, method = 'GET', body) => fetch(`${endpoint}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const patch = (path, data, token = owner.idToken) => request(`/${path}`, token, 'PATCH', { fields: fields(data) });
  const checkStatus = async (response, expected) => {
    assert.equal(response.status, expected, await response.clone().text());
  };
  const update = (path, data) => ({ update: { name: `${database}/${path}`, fields: fields(data) } });
  const remove = (path) => ({ delete: `${database}/${path}` });
  const commit = (writes) => request(':commit', owner.idToken, 'POST', { writes });
  const group = (path, name, token = owner.idToken) => request(`${path}:runQuery`, token, 'POST', {
    structuredQuery: { select: { fields: [{ fieldPath: '__name__' }] }, from: [{ collectionId: name, allDescendants: true }], limit: 8 },
  });

  // The emulator's admin token is only used to seed legacy orphans.
  const farmPaths = [crop, orphan, oldOrphan, archive, `${account}/common_expenses/current`,
    `${account}/crop_history/old`, `${account}/sales/old`, `${archive}/common_expenses_history/old`];
  for (const path of [account, otherCrop, ...farmPaths]) {
    await checkStatus(await patch(path, { name: 'Keep profile or clear farm data by path' }, 'owner'), 200);
  }
  await checkStatus(await patch(marketProfile, { status: 'published' }, 'owner'), 200);
  await checkStatus(await patch(marketListing, { status: 'active' }, 'owner'), 200);
  await checkStatus(await patch(marketOrder, { buyerUid: other.localId, sellerUid: owner.localId }, 'owner'), 200);
  const generation = randomUUID();
  const running = { generation, status: 'running', baseGeneration: null, batchToken: randomUUID() };
  await checkStatus(await patch(marker, running, other.idToken), 403);
  await checkStatus(await patch(marker, running), 200);
  await checkStatus(await request(`/${crop}`, owner.idToken, 'DELETE'), 403);
  await checkStatus(await patch(crop, { name: 'Rice', farmGeneration: generation }), 403);
  await checkStatus(await group('', 'expenses'), 403);
  await checkStatus(await group(`/${account}`, 'expenses', other.idToken), 403);
  for (const [parent, collection, path] of [[account, 'expenses', orphan], [archive, 'expenses_history', oldOrphan]]) {
    const response = await group(`/${parent}`, collection);
    await checkStatus(response, 200);
    assert.ok((await response.json()).some((row) => row.document?.name === `${database}/${path}`));
  }
  const batch = (paths) => [update(marker, { ...running, batchToken: randomUUID() }), ...paths.map(remove)];
  await checkStatus(await commit(batch([otherCrop])), 403);
  await checkStatus(await commit(batch([marketListing, marketOrder])), 403);
  await checkStatus(await commit(batch([orphan, oldOrphan])), 200);
  assert.equal((await (await request(`/${marker}`, owner.idToken)).json()).fields.status.stringValue, 'running');
  await checkStatus(await commit(batch(farmPaths.filter((path) => path !== orphan && path !== oldOrphan))), 200);
  await checkStatus(await commit([update(marker, { generation, status: 'complete' })]), 200);
  for (const path of farmPaths) await checkStatus(await request(`/${path}`, 'owner'), 404);
  for (const path of [account, otherCrop]) await checkStatus(await request(`/${path}`, 'owner'), 200);
  await checkStatus(await patch(crop, { name: 'Old crop', type: 'Rice' }), 403);
  await checkStatus(await patch(crop, { name: 'New crop', type: 'Rice', farmGeneration: generation }), 200);
  await checkStatus(await commit(batch([crop])), 403);
  await checkStatus(await request(`/${crop}`, owner.idToken), 200);
  await checkStatus(await request(`/${archive}`, owner.idToken, 'PATCH', {
    fields: {
      clearedThrough: { timestampValue: new Date(Date.now() - 1000).toISOString() },
      farmGeneration: { stringValue: generation },
    },
  }), 200);
  for (const path of [marketProfile, marketListing, marketOrder]) {
    await checkStatus(await request(`/${path}`, other.idToken), 200);
  }
});
