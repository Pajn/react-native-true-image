# Contributing

Contributions are always welcome, no matter how large or small!

We want this community to be friendly and respectful to each other. Please follow it in all your interactions with the project. Before contributing, please read the [code of conduct](./CODE_OF_CONDUCT.md).

## Development workflow

This project is a monorepo managed using [Yarn workspaces](https://yarnpkg.com/features/workspaces). It contains the following packages:

- The library package in the root directory.
- An example app in the `example/` directory.

To get started with the project, make sure you have the correct version of [Node.js](https://nodejs.org/) installed. See the [`.nvmrc`](./.nvmrc) file for the version used in this project.

Run `yarn` in the root directory to install the required dependencies for each package:

```sh
yarn
```

> Since the project relies on Yarn workspaces, you cannot use [`npm`](https://github.com/npm/cli) for development without manually migrating.

The [example app](/example/) demonstrates usage of the library. You need to run it to test any changes you make.

It is configured to use the local version of the library, so any changes you make to the library's source code will be reflected in the example app. Changes to the library's JavaScript code will be reflected in the example app without a rebuild, but native code changes will require a rebuild of the example app.

If you want to use Android Studio or Xcode to edit the native code, you can open the `example/android` or `example/ios` directories respectively in those editors. To edit the Objective-C or Swift files, open `example/ios/TrueImageExample.xcworkspace` in Xcode and find the source files at `Pods > Development Pods > react-native-true-image`.

To edit the Java or Kotlin files, open `example/android` in Android studio and find the source files at `react-native-true-image` under `Android`.

You can use various commands from the root directory to work with the project.

To start the packager:

```sh
yarn example start
```

To run the example app on Android:

```sh
yarn example android
```

To run the example app on iOS:

```sh
yarn example ios
```

To confirm that the app is running with the new architecture, you can check the Metro logs for a message like this:

```sh
Running "TrueImageExample" with {"fabric":true,"initialProps":{"concurrentRoot":true},"rootTag":1}
```

Note the `"fabric":true` and `"concurrentRoot":true` properties.

Make sure your code passes TypeScript:

```sh
yarn typecheck
```

To check for linting errors, run the following:

```sh
yarn lint
```

To fix formatting errors, run the following:

```sh
yarn lint --fix
```

Remember to add tests for your change if possible. Run the unit tests by:

```sh
yarn test
```



### Commit messages

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/):
`feat:`, `fix:`, `perf:`, `docs:`, `refactor:`, `test:`, `chore:` and so on, with
`!` or a `BREAKING CHANGE:` footer for breaking changes. The changelog and the
version bump are derived from them, so a `fix` becomes a patch release, a
`feat` a minor one, and a breaking change a major one. CI checks every commit
on a pull request with commitlint; run `yarn commitlint --from main` locally
to check yours.

### Releasing

Releases run from the **Release** workflow in GitHub Actions and publish to
npm with [trusted publishing](https://docs.npmjs.com/trusted-publishers).
There is no npm token in the repository or its secrets: npm accepts the
workflow's OpenID Connect identity because the package's trusted publisher
configuration on npmjs.com names this repository, the `release.yml` workflow
and the `npm` environment. Provenance is attached automatically.

To cut a release, open the Actions tab, pick **Release**, and run it against
`main`. Leave the increment empty to let the commits since the last tag decide
it, or choose one explicitly. The workflow runs lint, typecheck and tests,
then [release-it](https://github.com/release-it/release-it) bumps the version,
updates `CHANGELOG.md`, commits, tags, publishes, and creates the GitHub
release with the same notes.

The `npm` environment can carry a required-reviewer rule if releases should
need a second pair of eyes; the workflow already targets it.

#### First publish of the package

npm only lets a trusted publisher be configured on a package that already
exists, so the very first version is published from a maintainer's machine:

1. `npm login`, then `yarn release` and follow the prompts. release-it
   publishes with your session.
2. Register the workflow as a trusted publisher. The environment must match
   the one the workflow job runs in:

   ```sh
   npm trust github --file release.yml --repo <owner>/react-native-true-image --env npm --allow-publish
   ```

   The same can be done on npmjs.com under the package's settings. Check the
   result with `npm trust list react-native-true-image`.
3. Create the `npm` environment in the GitHub repository's settings.
4. `npm logout`. Every release from now on goes through the workflow.

### Scripts

The `package.json` file contains various scripts for common tasks:

- `yarn`: setup project by installing dependencies.
- `yarn typecheck`: type-check files with TypeScript.
  - `yarn lint`: lint files with [ESLint](https://eslint.org/).
    - `yarn test`: run unit tests with [Jest](https://jestjs.io/).
  - `yarn example start`: start the Metro server for the example app.
- `yarn example android`: run the example app on Android.
- `yarn example ios`: run the example app on iOS.
  
### Sending a pull request

> **Working on your first pull request?** You can learn how from this _free_ series: [How to Contribute to an Open Source Project on GitHub](https://app.egghead.io/playlists/how-to-contribute-to-an-open-source-project-on-github).

When you're sending a pull request:

- Prefer small pull requests focused on one change.
- Verify that linters and tests are passing.
- Review the documentation to make sure it looks good.
- Follow the pull request template when opening a pull request.
- For pull requests that change the API or implementation, discuss with maintainers first by opening an issue.
