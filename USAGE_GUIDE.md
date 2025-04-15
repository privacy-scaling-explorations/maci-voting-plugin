# Template Usage Guide

This guide will walk you through the process of writing the smart contract for a plugin. It will cover the following topics:

- [Dependency Installation](#dependency-installation)
- [Contracts](#contracts)

  - [Adapt the contracts](#adapt-template-contracts)
  - [testing](#testing)
    - [Unit Testing](#unit-testing)
    - [Integration Testing](#integration-testing)
  - [Deployment Scripts](#deployment-scripts)

## Dependency Installation

Before you begin, make sure you installed the necessary dependencies.
For detailed instructions, refer to the [README](README.md).

# Contracts

## Adapt template contracts

This template contains the boilerplate and it uses `MyPlugin` as the contracts names, in order to adapt them according to your needs follow the following steps:

1. Go to the `packages/contracts/src` folder and

   - adapt and rename the `MyPlugin.sol` plugin implementation contract (see [our docs](https://devs.aragon.org/docs/osx/how-to-guides/plugin-development/upgradeable-plugin/implementation)).
   - adapt and rename the `MyPluginSetup.sol` plugin setup contract (see [our docs](https://devs.aragon.org/docs/osx/how-to-guides/plugin-development/upgradeable-plugin/setup)).

2. adapt the release and build metadata for the plugin:

   - `build-metadata.json` and
   - `release-metadata.json`

   in the same folder. [Check our documentation](https://devs.aragon.org/docs/osx/how-to-guides/plugin-development/publication/metadata) on what the metadata files are about.

3. Finally, write the file names into the `packages/contracts/plugin-settings.ts` file and pick an ENS subdomain name according to the rules described in [our docs on ENS subdomain names](https://devs.aragon.org/docs/osx/how-it-works/framework/ens-names).

   ```ts
   export const PLUGIN_CONTRACT_NAME = 'MyPlugin'; // Replace this with plugin contract name you chose
   export const PLUGIN_SETUP_CONTRACT_NAME = 'MyPluginSetup'; // Replace this with the plugin setup contract name you chose.
   export const PLUGIN_REPO_ENS_NAME = 'my'; // Pick an ENS subdomain name under that will live under `plugin.dao.eth` domain (e.g., 'my' will result in 'my.plugin.dao.eth') for the plugin repository that will be created during deployment. Make sure that the subdomain is not already taken on the chain(s) you are planning to deploy to.
   ```

   When deploying the first version of your plugin, you don't need to change the following lines.

   ```ts
   export const VERSION = {
     release: 1, // Increment this number ONLY if breaking/incompatible changes were made. Updates between releases are NOT possible.
     build: 1, // Increment this number if non-breaking/compatible changes were made. Updates to newer builds are possible.
   };
   ```

   If you deploy upcoming versions of your plugin, you must increment the build or release number accordingly (see [our docs on versioning your plugin](https://devs.aragon.org/docs/osx/how-to-guides/plugin-development/publication/versioning)).

### Testing

The `packages/contracts/test` folder contains pre-written unit and integration tests that you can adapt and extend.

#### Unit Testing

The `packages/contracts/test/10_unit-testing` folder contains

- plugin implementation contract unit tests in the `11_plugin.ts` file
- containing plugin setup contract unit tests in the `12_plugin-setup.ts` file

Adapt and extend the tests according to your changes and plugin features.

#### Integration Testing

The `packages/contracts/test/20_integration-testing` folder contains

- deployment tests in the `21_deployment.ts` file
  - testing that the deploy scripts publishes the plugin and sets the maintainer permissions correctly
- setup processing tests in the `22_setup-processing.ts` file
  - testing that Aragon OSx `PluginSetupProcessor` can [apply a plugin setup](https://devs.aragon.org/docs/osx/how-it-works/framework/plugin-management/plugin-setup/#what-happens-during-the-preparation-application) correctly

The prior tests if your plugin can be deployed

### Deployment Scripts

The standard deploy scripts in the `packages/contracts/deploy` should already be sufficient to deploy the first and upcoming versions of your plugin as well as upgrade your plugin repo. If your deployment has special requirements, adapt the files.

- `00_info/01_account_info.ts`
  - Prints information on the used networks and used account.
- `10_create_repo/11_create_repo.ts`
  - Creates a plugin repo with an ENS subdomain name under the `plugin.dao.eth` parent domain if the ENS name is not taken already.
- `20_new_version/21_setup.ts`
  - Deploys the plugin setup contract
- `20_new_version/22_setup_conclude.ts`
  - Fetches the plugin setup and implementation contract and queues it for block explorer verification.
- `20_new_version/23_publish.ts`
  - Publishes the plugin setup contract on the plugin repo created in `10_repo/11_create_repo.ts`
- `30_upgrade_repo/31a_upgrade_and_reinitialize_repo.ts`
  - Upgrades the plugin repo to the latest Aragon OSx protocol version and reinitializes it.
- `30_upgrade_repo/31b_upgrade_repo.ts`
  - Upgrades the plugin repo to the latest Aragon OSx protocol version.
- `40_conclude/41_conclude.ts`
  - Prints information on the used account's balance after deployment.
- `50_verification/51_verify_contracts.ts`
  - Verifies all deployed contracts.
