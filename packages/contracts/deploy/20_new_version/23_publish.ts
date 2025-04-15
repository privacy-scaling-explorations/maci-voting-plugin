import {
  METADATA,
  PLUGIN_CONTRACT_NAME,
  PLUGIN_REPO_ENS_SUBDOMAIN_NAME,
  PLUGIN_SETUP_CONTRACT_NAME,
  VERSION,
} from '../../plugin-settings';
import {
  findPluginRepo,
  getPastVersionCreatedEvents,
  impersonatedManagementDaoSigner,
  isLocal,
  pluginEnsDomain,
  isValidAddress,
  publishPlaceholderVersion,
} from '../../utils/helpers';
import {PLUGIN_REPO_PERMISSIONS, uploadToPinata} from '@aragon/osx-commons-sdk';
import {PluginRepo__factory} from '@aragon/osx-ethers';
import {writeFile} from 'fs/promises';
import {ethers} from 'hardhat';
import {DeployFunction} from 'hardhat-deploy/types';
import {HardhatRuntimeEnvironment} from 'hardhat/types';
import path from 'path';

/**
 * Publishes the plugin setup in the plugin repo as a new version as specified in the `./plugin-settings.ts` file.
 * @param {HardhatRuntimeEnvironment} hre
 */
const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  console.log(
    `Publishing ${PLUGIN_SETUP_CONTRACT_NAME} as v${VERSION.release}.${VERSION.build} in the "${PLUGIN_REPO_ENS_SUBDOMAIN_NAME}" plugin repo`
  );

  const {deployments} = hre;
  const [deployer] = await hre.ethers.getSigners();

  let releaseMetadataURI = '0x';
  let buildMetadataURI = '0x';

  if (!isLocal(hre)) {
    if (!process.env.PUB_PINATA_JWT) {
      throw Error('PUB_PINATA_JWT is not set');
    }

    // Upload the metadata to IPFS
    releaseMetadataURI = await uploadToPinata(
      METADATA.release,
      `${PLUGIN_REPO_ENS_SUBDOMAIN_NAME}-release-metadata`,
      process.env.PUB_PINATA_JWT
    );
    buildMetadataURI = await uploadToPinata(
      METADATA.build,
      `${PLUGIN_REPO_ENS_SUBDOMAIN_NAME}-build-metadata`,
      process.env.PUB_PINATA_JWT
    );
  }
  console.log(`Uploaded release metadata: ${releaseMetadataURI}`);
  console.log(`Uploaded build metadata: ${buildMetadataURI}`);

  // Get PluginSetup
  const setup = await deployments.get(PLUGIN_SETUP_CONTRACT_NAME);

  // Get PluginRepo
  const {pluginRepo, ensDomain} = await findPluginRepo(hre);
  if (pluginRepo === null) {
    throw `PluginRepo '${ensDomain}' does not exist yet.`;
  }

  // Check release number
  const latestRelease = await pluginRepo.latestRelease();
  if (VERSION.release > latestRelease + 1) {
    throw Error(
      `Publishing with release number ${VERSION.release} is not possible.
        The latest release is ${latestRelease} and the next release you can publish is release number ${
        latestRelease + 1
      }.`
    );
  }

  // Check build number
  const latestBuild = (await pluginRepo.buildCount(VERSION.release)).toNumber();
  if (latestBuild == 0 && VERSION.build > 1) {
    // it means there's no build yet on the repo on the specific VERSION.release
    // and build version in the plugin settings is > 1, meaning that
    // it must push placeholder contracts and as the last one, push the actual plugin setup.
  } else {
    if (VERSION.build < latestBuild) {
      throw Error(
        `Publishing with build number ${VERSION.build} is not possible. The latest build is ${latestBuild}. Aborting publication...`
      );
    }
    if (VERSION.build > latestBuild + 1) {
      throw Error(
        `Publishing with build number ${VERSION.build} is not possible.
        The latest build is ${latestBuild} and the next release you can publish is release number ${
          latestBuild + 1
        }. Aborting publication...`
      );
    }
  }

  if (setup == undefined || setup?.receipt == undefined) {
    throw Error('setup deployment unavailable');
  }

  const isDeployerMaintainer = await pluginRepo.isGranted(
    pluginRepo.address,
    deployer.address,
    PLUGIN_REPO_PERMISSIONS.MAINTAINER_PERMISSION_ID,
    []
  );

  // If this is a local deployment and the deployer doesn't have `MAINTAINER_PERMISSION_ID`  permission
  // we impersonate the management DAO for integration testing purposes.
  const signer =
    isDeployerMaintainer || !isLocal(hre)
      ? deployer
      : await impersonatedManagementDaoSigner(hre);

  // Check if the signer has the permission to maintain the plugin repo
  if (
    await pluginRepo.isGranted(
      pluginRepo.address,
      signer.address,
      PLUGIN_REPO_PERMISSIONS.MAINTAINER_PERMISSION_ID,
      []
    )
  ) {
    if (latestBuild == 0 && VERSION.build > 1) {
      // We are publishing the first version as build > 1.
      // So we need to publish placeholders first..
      const placeholderSetup = process.env.PLACEHOLDER_SETUP;

      if (!placeholderSetup || !isValidAddress(placeholderSetup)) {
        throw new Error(
          'Aborting. Placeholder setup not defined in .env or is not a valid address (is not an address or is address zero)'
        );
      }
      await publishPlaceholderVersion(
        placeholderSetup,
        VERSION.build,
        VERSION.release,
        pluginRepo,
        signer
      );
    }

    // Create the new version
    const tx = await pluginRepo
      .connect(signer)
      .createVersion(
        VERSION.release,
        setup.address,
        ethers.utils.hexlify(ethers.utils.toUtf8Bytes(buildMetadataURI)),
        ethers.utils.hexlify(ethers.utils.toUtf8Bytes(releaseMetadataURI))
      );

    await tx.wait();

    const version = await pluginRepo['getLatestVersion(uint8)'](
      VERSION.release
    );
    if (VERSION.release !== version.tag.release) {
      throw Error('something went wrong');
    }

    console.log(
      `Published ${PLUGIN_SETUP_CONTRACT_NAME} at ${setup.address} in PluginRepo ${PLUGIN_REPO_ENS_SUBDOMAIN_NAME} at ${pluginRepo.address}.`
    );
  } else {
    // The deployer does not have `MAINTAINER_PERMISSION_ID` permission and we are not deploying to a production network,
    // so we write the data into a file for a management DAO member to create a proposal from it.
    const pluginRepoInterface = PluginRepo__factory.createInterface();
    const versionData = {
      _release: VERSION.release,
      _pluginSetup: setup.address,
      _buildMetadata: ethers.utils.hexlify(
        ethers.utils.toUtf8Bytes(buildMetadataURI)
      ),
      _releaseMetadata: ethers.utils.hexlify(
        ethers.utils.toUtf8Bytes(releaseMetadataURI)
      ),
    };

    const calldata = pluginRepoInterface.encodeFunctionData('createVersion', [
      versionData._release,
      versionData._pluginSetup,
      versionData._buildMetadata,
      versionData._releaseMetadata,
    ]);

    const data = {
      proposalTitle: `Publish '${PLUGIN_CONTRACT_NAME}' plugin v${VERSION.release}.${VERSION.build}`,
      proposalSummary: `Publishes v${VERSION.release}.${VERSION.build} of the '${PLUGIN_CONTRACT_NAME}' plugin in the '${ensDomain}' plugin repo.`,
      proposalDescription: `\n- Publishes the **'${PLUGIN_SETUP_CONTRACT_NAME}'** deployed at **'${setup.address}'** as **v${VERSION.release}.${VERSION.build}** in the **'${ensDomain}'** plugin repo at **'${pluginRepo.address}'**, with release metadata **'${releaseMetadataURI}'** and (immutable) build metadata **'${buildMetadataURI}'**.`,
      actions: [
        {
          to: pluginRepo.address,
          value: 0,
          data: calldata,
          createVersion: versionData,
        },
      ],
    };

    const path = `./createVersionProposalData-${hre.network.name}.json`;
    await writeFile(path, JSON.stringify(data, null, 2));
    console.log(
      `Saved data to '${path}'. Use this to create a proposal on the managing DAO calling the 'createVersion' function on the ${ensDomain} plugin repo deployed at ${pluginRepo.address}.`
    );
  }
};

export default func;
func.tags = [PLUGIN_SETUP_CONTRACT_NAME, 'NewVersion', 'Publication'];

/**
 * Skips the publication of the specified version if it already exists in the plugin repo.
 * @param {HardhatRuntimeEnvironment} hre
 */
func.skip = async (hre: HardhatRuntimeEnvironment) => {
  console.log(`\n📢 ${path.basename(__filename)}:`);

  // Get PluginRepo
  const {pluginRepo} = await findPluginRepo(hre);
  if (pluginRepo === null) {
    throw `PluginRepo '${pluginEnsDomain(hre)}' does not exist yet.`;
  }

  try {
    const pastVersions = await getPastVersionCreatedEvents(pluginRepo);

    // Check if the version was published already
    const filteredLogs = pastVersions.filter(
      items =>
        items.event.args.release === VERSION.release &&
        items.event.args.build === VERSION.build
    );

    if (filteredLogs.length !== 0) {
      console.log(
        `Build number ${VERSION.build} has already been published for release ${VERSION.release}. Skipping publication...`
      );
      return true;
    }
  } catch (error) {
    console.log(`Could not get the previous version ${error}.`);
  }

  return false;
};
