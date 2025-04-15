// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

/// @dev DO NOT USE IN PRODUCTION!
contract CustomExecutorMock {
    error FailedCustom();

    event ExecutedCustom();

    function execute(
        bytes32 callId,
        Action[] memory,
        uint256
    ) external returns (bytes[] memory execResults, uint256 failureMap) {
        (execResults, failureMap);

        if (callId == bytes32(0)) {
            revert FailedCustom();
        } else {
            emit ExecutedCustom();
        }
    }
}
