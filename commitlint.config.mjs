// Commit messages feed the changelog, so they follow Conventional Commits.
// CI checks every commit on a pull request against this config.
export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'body-max-line-length': [0],
    'footer-max-line-length': [0],
  },
};
