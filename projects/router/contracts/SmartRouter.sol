// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '@pancakeswap/v3-periphery/contracts/base/SelfPermit.sol';
import '@pancakeswap/v3-periphery/contracts/base/PeripheryImmutableState.sol';

import './interfaces/ISmartRouter.sol'; // this one itself
import './V2SwapRouter.sol'; // done
import './V3SwapRouter.sol';
import './StableSwapRouter.sol'; // done
import './base/ApproveAndCall.sol';
import './base/MulticallExtended.sol';

/// @title Pancake Smart Router
contract SmartRouter is
    ISmartRouter,
    V2SwapRouter,
    V3SwapRouter,
    StableSwapRouter,
    ApproveAndCall,
    MulticallExtended, // This allows users to batch multiple calls into a single transaction, improving gas efficiency and reducing the number of blockchain interactions.
    SelfPermit
    /*
    Permission Management:
    The contract utilizes the SelfPermit feature, which likely enables users to grant specific permissions for token transfers and interactions. This feature can enhance the contract's flexibility when working with different tokens and token standards.
    */
{
    constructor(
        address _factoryV2,
        address _deployer,
        address _factoryV3,
        address _positionManager,
        address _stableFactory,
        address _stableInfo,
        address _WETH9
    )
        ImmutableState(_factoryV2, _positionManager)
        PeripheryImmutableState(_deployer, _factoryV3, _WETH9)
        StableSwapRouter(_stableFactory, _stableInfo)
    {}
}
