# Branch protection setup

Branch protection ensures changes reach the default branch only via pull request and with a passing CI build. This is configured in the GitHub web UI; it cannot be set from repository files.

## Steps

1. Open the repository **Settings** on GitHub.
2. Go to **Branches** (under "Code and automation").
3. Under **Branch protection rules**, click **Add branch protection rule** (or edit the existing rule).
4. **Branch name pattern**: `main` or `master` (whichever is your default branch).
5. Enable:
   - **Require a pull request before merging** (optionally enable **Require approvals**).
   - **Require status checks to pass before merging**.
6. Under **Status checks that are required**:
   - Use **Search for status checks** and select the three **Build GDExtension** jobs: `build-linux`, `build-windows`, `build-macos` (see `.github/workflows/build.yml`).
   - Alternatively, require **Build GDExtension** as a single check if the workflow appears that way in the UI.
7. Save with **Create** or **Save changes**.

## Outcome

- Pull requests can merge only when the build workflow succeeds.
- Direct pushes to the protected branch are blocked (except for admins, unless that bypass is allowed).
- The `main`/`master` branch stays buildable.
