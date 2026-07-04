# Security

Current MVP controls:

- Passwords are hashed.
- JWT bearer tokens protect all private endpoints.
- Circle membership and roles are enforced server-side.
- Viewers only see approved memories by default.
- Asset retrieval requires authentication and circle membership.
- Uploads are MIME checked and decoded with Pillow before storage.
- Responses expose API asset URLs, not raw server paths.
- Write actions create activity log entries.

Known limitations:

- Development JWT secret must be changed before deployment.
- Invite simulation creates accounts with a temporary password.
- Rate limiting, email verification, and password reset are not implemented yet.
- SQLite is suitable for demo/dev only.
