# Release Please Setup

This repository expects a GitHub Actions secret named `RELEASE_PLEASE_TOKEN`.

The workflow runs `release-please` through the CLI on Node 24 instead of
`googleapis/release-please-action@v4`. This avoids the GitHub Actions Node 20
deprecation warning while keeping the same release automation behavior.

Why:
- `release-please-action` needs `contents: write`, `issues: write`, and `pull-requests: write`.
- The default `GITHUB_TOKEN` can still be blocked from creating PRs if the repository setting `Allow GitHub Actions to create and approve pull requests` is disabled.
- A dedicated PAT also allows follow-up workflows on release PRs to run normally.

Recommended setup:
1. Create a fine-grained personal access token for this repository.
2. Grant at least `Contents: Read and write` and `Pull requests: Read and write`.
3. Save it as the repository secret `RELEASE_PLEASE_TOKEN`.
4. Re-run `.github/workflows/release.yml`.

Workflow behavior:
1. `release-pr` creates or updates the Release PR on pushes to `main`.
2. `github-release` creates the tag and GitHub Release after that Release PR is merged.
3. There is no placeholder post-release job in the same workflow, so you will not
   see a confusing `skipped` job when only the Release PR changes.

Alternative setup:
1. Open `Settings -> Actions -> General`.
2. Under `Workflow permissions`, select `Read and write permissions`.
3. Enable `Allow GitHub Actions to create and approve pull requests`.
4. If you use this mode, the built-in `GITHUB_TOKEN` can create the release PR, but downstream workflows triggered by that PR may still be skipped.

References:
- GitHub Actions repository settings: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository
- release-please-action README: https://github.com/googleapis/release-please-action/blob/main/README.md
- release-please CLI: https://github.com/googleapis/release-please
