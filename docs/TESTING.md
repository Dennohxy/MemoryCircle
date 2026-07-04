# Testing

Backend tests cover:

- Registration and login.
- Circle creation.
- Member role authorization.
- Memory creation.
- Pending-to-approved workflow.
- Rejection workflow.
- Asset upload and thumbnail retrieval.
- Album page generation.

Run:

```bash
cd backend/api
python3 -m pytest
```

Flutter smoke test, when Flutter is installed:

```bash
cd apps/mobile_desktop_flutter
flutter test
```
