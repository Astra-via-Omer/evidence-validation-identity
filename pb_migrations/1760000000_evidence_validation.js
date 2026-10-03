migrate((app) => {
  const users = new Collection({
    type: 'auth', name: 'ev_users',
    listRule: 'id = @request.auth.id', viewRule: 'id = @request.auth.id',
    createRule: '', updateRule: 'id = @request.auth.id', deleteRule: null,
    fields: [{ name: 'name', type: 'text', required: true, min: 2, max: 100 }],
    passwordAuth: { enabled: true, identityFields: ['email'] },
    authToken: { duration: 3600 },
  });
  app.save(users);
  const jobs = new Collection({
    type: 'base', name: 'ev_jobs',
    listRule: '@request.auth.id != "" && (owner = @request.auth.id || (visibility = "public" && status = "open"))',
    viewRule: '@request.auth.id != "" && (owner = @request.auth.id || (visibility = "public" && status = "open"))',
    createRule: '@request.auth.verified = true && owner = @request.auth.id && status = "draft" && feeBps = 1000',
    updateRule: null, deleteRule: null,
    fields: [
      { name: 'owner', type: 'relation', collectionId: users.id, required: true, maxSelect: 1 },
      { name: 'title', type: 'text', required: true, min: 5, max: 180 },
      { name: 'claim', type: 'text', required: true, min: 10, max: 10000 },
      { name: 'quote', type: 'text', required: true, min: 5, max: 10000 },
      { name: 'sourceUrl', type: 'url', required: true },
      { name: 'location', type: 'text', required: true, max: 500 },
      { name: 'relationship', type: 'select', required: true, maxSelect: 1, values: ['supports', 'challenges', 'context'] },
      { name: 'visibility', type: 'select', required: true, maxSelect: 1, values: ['private', 'public'] },
      { name: 'status', type: 'select', required: true, maxSelect: 1, values: ['draft', 'open', 'closed'] },
      { name: 'rewardCents', type: 'number', min: 0, max: 1000000, onlyInt: true },
      { name: 'feeBps', type: 'number', min: 0, max: 10000, onlyInt: true },
      { name: 'created', type: 'autodate', onCreate: true },
      { name: 'updated', type: 'autodate', onCreate: true, onUpdate: true },
    ],
    indexes: ['CREATE INDEX idx_ev_jobs_owner ON ev_jobs (owner)'],
  });
  app.save(jobs);
  const reviews = new Collection({
    type: 'base', name: 'ev_reviews',
    listRule: '@request.auth.id != "" && (reviewer = @request.auth.id || job.owner = @request.auth.id)',
    viewRule: '@request.auth.id != "" && (reviewer = @request.auth.id || job.owner = @request.auth.id)',
    createRule: '@request.auth.verified = true && reviewer = @request.auth.id && job.status = "open" && job.visibility = "public" && job.owner != @request.auth.id && status = "submitted" && conflictFree = true',
    updateRule: null, deleteRule: null,
    fields: [
      { name: 'job', type: 'relation', collectionId: jobs.id, required: true, maxSelect: 1 },
      { name: 'reviewer', type: 'relation', collectionId: users.id, required: true, maxSelect: 1 },
      { name: 'verdict', type: 'select', required: true, maxSelect: 1, values: ['supports', 'challenges', 'context', 'insufficient', 'mismatch'] },
      { name: 'reasoning', type: 'text', required: true, min: 40, max: 10000 },
      { name: 'quote', type: 'text', required: true, min: 5, max: 10000 },
      { name: 'location', type: 'text', required: true, max: 500 },
      { name: 'conflictFree', type: 'bool', required: true },
      { name: 'status', type: 'select', required: true, maxSelect: 1, values: ['submitted', 'accepted', 'disputed', 'rejected'] },
      { name: 'created', type: 'autodate', onCreate: true },
    ],
    indexes: ['CREATE UNIQUE INDEX idx_ev_review_once ON ev_reviews (job, reviewer)'],
  });
  app.save(reviews);
  app.save(new Collection({
    type: 'base', name: 'ev_api_keys',
    listRule: 'owner = @request.auth.id', viewRule: 'owner = @request.auth.id',
    createRule: null, updateRule: null, deleteRule: null,
    fields: [
      { name: 'owner', type: 'relation', collectionId: users.id, required: true, maxSelect: 1 },
      { name: 'name', type: 'text', required: true, max: 80 },
      { name: 'tokenHash', type: 'text', required: true, hidden: true, min: 64, max: 64 },
      { name: 'scopes', type: 'select', required: true, maxSelect: 4, values: ['jobs:read', 'jobs:write', 'reviews:write', 'bundles:read'] },
      { name: 'expiresAt', type: 'date', required: true },
      { name: 'revoked', type: 'bool' },
      { name: 'created', type: 'autodate', onCreate: true },
    ],
    indexes: ['CREATE UNIQUE INDEX idx_ev_key_hash ON ev_api_keys (tokenHash)'],
  }));
}, (app) => {
  for (const name of ['ev_api_keys', 'ev_reviews', 'ev_jobs', 'ev_users']) app.delete(app.findCollectionByNameOrId(name));
});
