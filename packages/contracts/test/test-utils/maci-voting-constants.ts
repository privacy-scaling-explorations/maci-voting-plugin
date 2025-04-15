import {IMaciVoting} from '../../typechain/src/MaciVoting';
import {pctToRatio, TIME} from '@aragon/osx-commons-sdk';
import {Keypair, PrivKey} from 'maci-domainobjs';

export const defaultMaci = '0xC6Ec20B49957851C4BF6552bE7F68F124a6be98C'; // arbitrum sepolia

export const coordinatorMACIKeyPair = new Keypair(
  PrivKey.deserialize(
    'macisk.bdd73f1757f75261a0c9997def6cd47519cad2856347cdc6fd30718999576860'
  )
);
export const defaultCoordinatorPubKey =
  coordinatorMACIKeyPair.pubKey.asContractParam();

export const defaultVotingSettings: IMaciVoting.VotingSettingsStruct = {
  minParticipation: pctToRatio(20),
  minDuration: Number(TIME.HOUR),
  minProposerVotingPower: 0,
};

const cleanObject = (obj: any) => {
  return Object.keys(obj)
    .filter(key => !isNaN(Number(key))) // only keep numeric keys
    .sort((a, b) => Number(a) - Number(b)) // sort numeric keys in order
    .map(key => obj[key]); // return only the values
};

export const getOnlyTheArrayResults = (results: any[]) => {
  if (Array.isArray(results)) {
    return results.map(cleanObject);
  }
  return cleanObject(results);
};
