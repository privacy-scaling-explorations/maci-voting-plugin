import {TestGovernanceERC20} from '@aragon/osx-ethers';
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import {expect} from 'chai';
import {BigNumber, Contract} from 'ethers';
import {ethers} from 'hardhat';

export enum VoteOption {
  None,
  Abstain,
  Yes,
  No,
}

export enum VotingMode {
  Standard,
  EarlyExecution,
  VoteReplacement,
}

export async function voteWithSigners(
  votingContract: Contract,
  proposalId: BigNumber,
  ballot: {
    yes: SignerWithAddress[];
    no: SignerWithAddress[];
    abstain: SignerWithAddress[];
  }
) {
  let promises = ballot.yes.map(signer =>
    votingContract.connect(signer).vote(proposalId, VoteOption.Yes, false)
  );

  promises = promises.concat(
    ballot.no.map(signer =>
      votingContract.connect(signer).vote(proposalId, VoteOption.No, false)
    )
  );
  promises = promises.concat(
    ballot.abstain.map(signer =>
      votingContract.connect(signer).vote(proposalId, VoteOption.Abstain, false)
    )
  );

  await Promise.all(promises);
}

export async function setBalances(
  token: TestGovernanceERC20,
  balances: {receiver: string; amount: number | BigNumber}[]
) {
  for (let i = 0; i < balances.length; i++) {
    await token.setBalance(balances[i].receiver, balances[i].amount);
  }
}

export async function setTotalSupply(
  token: TestGovernanceERC20,
  totalSupply: number
) {
  await ethers.provider.send('evm_mine', []);
  const block = await ethers.provider.getBlock('latest');

  const currentTotalSupply: BigNumber = await token.getPastTotalSupply(
    block.number - 1
  );

  await token.setBalance(
    `0x${'0'.repeat(39)}1`, // address(1)
    BigNumber.from(totalSupply).sub(currentTotalSupply)
  );
}

export async function getTime(): Promise<number> {
  return (await ethers.provider.getBlock('latest')).timestamp;
}

export async function advanceTime(time: number) {
  await ethers.provider.send('evm_increaseTime', [time]);
  await ethers.provider.send('evm_mine', []);
}

export async function advanceTimeTo(timestamp: number) {
  const delta = timestamp - (await getTime());
  await advanceTime(delta);
}

export async function advanceAfterVoteEnd(endDate: number) {
  await advanceTimeTo(endDate);
  expect(await getTime()).to.be.greaterThanOrEqual(endDate);
}
