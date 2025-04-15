import {DAO, PluginRepo} from '@aragon/osx-ethers';
import {defaultAbiCoder} from '@ethersproject/abi';
import {expect} from 'chai';
import {Contract, errors} from 'ethers';
import hre, {ethers} from 'hardhat';

// The protocol version number of contracts not having a `getProtocolVersion()` function because they don't inherit from `ProtocolVersion.sol` yet.
export const IMPLICIT_INITIAL_PROTOCOL_VERSION: [number, number, number] = [
  1, 0, 0,
];

// See https://eips.ethereum.org/EIPS/eip-1967
export const ERC1967_IMPLEMENTATION_SLOT =
  '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc'; // bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1)

export const OZ_INITIALIZED_SLOT_POSITION = 0;

type options = {
  args?: Record<string, any>;
  initArgs?: Record<string, any>;
  initializerName?: string | undefined;
  reinitializerName?: string | undefined;
  reinitArgs?: Record<string, any>;
};

// Deploys a proxy and a new implementation from the same factory and checks that the upgrade works.
export async function deployAndUpgradeSelfCheck(
  deployer: number,
  upgrader: number,
  {args = {}, initArgs = {}, initializerName = undefined}: options,
  from: string,
  to: string,
  upgradePermissionId: string,
  managingContract?: DAO | PluginRepo | undefined
) {
  const deployerSigner = (await hre.ethers.getSigners())[deployer];
  const upgraderSigner = (await hre.ethers.getSigners())[upgrader];

  // Deploy proxy and implementation
  const proxy = await hre.wrapper.deployProxy(deployer, from, {
    args: Object.values(args),
    initArgs: Object.values(initArgs),
    proxySettings: {
      initializer: initializerName,
    },
  });

  // Grant the upgrade permission
  const grantArgs: [string, string, string] = [
    proxy.address,
    upgraderSigner.address,
    upgradePermissionId,
  ];

  // Check if the contract is a permission manager itself
  if (managingContract === undefined) {
    await expect(
      hre.wrapper.upgradeProxy(upgrader, proxy.address, to, {
        args: Object.values(args),
      })
    )
      .to.be.revertedWithCustomError(proxy, 'Unauthorized')
      .withArgs(...grantArgs);

    await proxy.connect(deployerSigner).grant(...grantArgs);
  }
  // Or if the permission manager is located in a different contract
  else {
    await expect(
      hre.wrapper.upgradeProxy(upgrader, proxy.address, to, {
        args: Object.values(args),
      })
    )
      .to.be.revertedWithCustomError(proxy, 'DaoUnauthorized')
      .withArgs(managingContract.address, ...grantArgs);

    await managingContract.connect(deployerSigner).grant(...grantArgs);
  }

  // Deploy a new implementation (the same contract at a different address)
  const toImplementation = (await hre.wrapper.deploy(to)).address;

  // Confirm that the two implementations are different
  const fromImplementation = await ethers.provider
    .getStorageAt(proxy.address, ERC1967_IMPLEMENTATION_SLOT)
    .then(encoded => defaultAbiCoder.decode(['address'], encoded)[0]);

  expect(toImplementation).to.not.equal(fromImplementation);

  // Upgrade from the old to the new implementation
  await proxy.connect(upgraderSigner).upgradeTo(toImplementation);

  // Confirm that the proxy points to the new implementation
  const implementationAfterUpgrade = await ethers.provider
    .getStorageAt(proxy.address, ERC1967_IMPLEMENTATION_SLOT)
    .then(encoded => defaultAbiCoder.decode(['address'], encoded)[0]);
  expect(implementationAfterUpgrade).to.equal(toImplementation);
}

// Deploys a proxy and a new implementation via two different factories and checks that the upgrade works.
export async function deployAndUpgradeFromToCheck(
  deployer: number,
  upgrader: number,
  {
    args = {},
    initArgs = {},
    initializerName = undefined,
    reinitializerName = undefined,
    reinitArgs = undefined,
  }: options,
  from: string,
  to: string,
  upgradePermissionId: string,
  managingDao?: DAO | PluginRepo
): Promise<{
  proxy: Contract;
  fromImplementation: string;
  toImplementation: string;
}> {
  const deployerSigner = (await hre.ethers.getSigners())[deployer];
  const upgraderSigner = (await hre.ethers.getSigners())[upgrader];

  // Deploy proxy and implementation
  let proxy = await hre.wrapper.deployProxy(deployer, from, {
    args: Object.values(args),
    initArgs: Object.values(initArgs),
    proxySettings: {
      initializer: initializerName,
    },
  });

  const fromImplementation = await ethers.provider
    .getStorageAt(proxy.address, ERC1967_IMPLEMENTATION_SLOT)
    .then(encoded => defaultAbiCoder.decode(['address'], encoded)[0]);

  // Grant the upgrade permission
  const grantArgs: [string, string, string] = [
    proxy.address,
    upgraderSigner.address,
    upgradePermissionId,
  ];

  // Check if the contract is a permission manager itself
  if (managingDao === undefined) {
    await expect(
      hre.wrapper.upgradeProxy(upgrader, proxy.address, to, {
        args: Object.values(args),
      })
    )
      .to.be.revertedWithCustomError(proxy, 'Unauthorized')
      .withArgs(...grantArgs);

    await proxy.connect(deployerSigner).grant(...grantArgs);
  }
  // Or if the permission manager is located in a different contract
  else {
    await expect(
      hre.wrapper.upgradeProxy(upgrader, proxy.address, to, {
        args: Object.values(args),
      })
    )
      .to.be.revertedWithCustomError(proxy, 'DaoUnauthorized')
      .withArgs(managingDao.address, ...grantArgs);

    await managingDao.connect(deployerSigner).grant(...grantArgs);
  }

  let call;
  if (reinitializerName && reinitArgs) {
    call = {
      fn: reinitializerName,
      args: reinitArgs,
    };
  }

  // Upgrade the proxy to a new implementation from a different factory
  proxy = await hre.wrapper.upgradeProxy(upgrader, proxy.address, to, {
    args: Object.values(args),
    call: call,
  });

  const toImplementation = await ethers.provider
    .getStorageAt(proxy.address, ERC1967_IMPLEMENTATION_SLOT)
    .then(encoded => defaultAbiCoder.decode(['address'], encoded)[0]);
  return {proxy, fromImplementation, toImplementation};
}

export async function getProtocolVersion(
  contract: Contract
): Promise<[number, number, number]> {
  let protocolVersion: [number, number, number];
  try {
    contract.interface.getFunction('protocolVersion');
    protocolVersion = await contract.protocolVersion();
  } catch (error: unknown) {
    if (
      error instanceof Error &&
      'code' in error &&
      error.code === errors.INVALID_ARGUMENT
    ) {
      protocolVersion = IMPLICIT_INITIAL_PROTOCOL_VERSION;
    } else {
      throw error;
    }
  }
  return protocolVersion;
}
