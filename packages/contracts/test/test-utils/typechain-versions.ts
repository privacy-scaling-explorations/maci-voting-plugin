/// Typechain will sometimes by default link to the wrong version of the contract, when we have name collisions
/// The version specified in src is the factory and contract without the version number.
/// Import as needed in the test files, and use the correct version of the contract.

/* MaciVoting */
export {MaciVoting__factory} from '../../typechain/factories/src/MaciVoting__factory';
export type {MaciVoting} from '../../typechain/src/MaciVoting';

/* MaciVotingSetup */
export {MaciVotingSetup__factory} from '../../typechain';
export {MaciVotingSetup} from '../../typechain';
