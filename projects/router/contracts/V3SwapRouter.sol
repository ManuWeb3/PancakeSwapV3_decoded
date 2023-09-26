// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '@pancakeswap/v3-core/contracts/libraries/SafeCast.sol';
import '@pancakeswap/v3-core/contracts/libraries/TickMath.sol';
import '@pancakeswap/v3-periphery/contracts/libraries/Path.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

import './interfaces/IV3SwapRouter.sol'; // this itself
import './base/PeripheryPaymentsWithFeeExtended.sol';
import './base/OracleSlippage.sol';
import './libraries/Constants.sol';
import './libraries/SmartRouterHelper.sol'; // done

/// @title PancakeSwap V3 Swap Router
/// @notice Router for stateless execution of swaps against PancakeSwap V3

/*
In summary, the V3SwapRouter contract is an abstract contract that provides essential functions and mechanisms for 
INTERACTING with PancakeSwap V3 L-POOLS on the Binance Smart Chain. It enables users to perform various types of swaps, including exact input and exact output swaps, while efficiently handling multi-hop swaps and ensuring the security and correctness of the transactions.
*/

abstract contract V3SwapRouter is IV3SwapRouter, PeripheryPaymentsWithFeeExtended, OracleSlippage, ReentrancyGuard {
    using Path for bytes;
    using SafeCast for uint256;

    /*
    Amount Caching:
    To handle exact output swaps efficiently, the contract caches the computed amount in (amountInCached) for later use in the transaction. This caching improves gas efficiency when executing swaps.
    */

    /// @dev Used as the placeholder value for amountInCached, because the [computed amount in for an exact output swap]
    /// can never actually be this value
    uint256 private constant DEFAULT_AMOUNT_IN_CACHED = type(uint256).max;

    /// @dev Transient storage variable used for returning the [computed amount in for an exact output swap.]
    uint256 private amountInCached = DEFAULT_AMOUNT_IN_CACHED;

    // The SwapCallbackData struct is used within the context of the PancakeSwap V3 Swap Router contract to [encode and pass data related to a swap callback.]
    // During a swap callback, this SwapCallbackData struct is encoded and passed as a parameter to the callback function. It allows the contract to access important information about the swap, such as the token path and the entity responsible for payment. This information is crucial for properly executing and routing swaps within the PancakeSwap V3 ecosystem, especially in cases where multi-hop swaps or complex routing is involved.
    // In summary, the SwapCallbackData struct is a data structure used to encapsulate and pass essential data about a swap, including the token path and payer information, within the PancakeSwap V3 Swap Router contract.
    struct SwapCallbackData {
        bytes path; // path: This field is of type bytes and is used to encode the token path for the swap. The token path represents the sequence of tokens involved in the swap, including the input token, output token, and any intermediary tokens if the swap involves multiple pools. The path is encoded as bytes to efficiently store the data required to reconstruct the token path. Storing/keeping in the type of a dynamic array of addresses:path can be costly to access/store
        address payer; // payer: This field is of type address and represents the address of the entity that is responsible for paying for the swap. In the context of the PancakeSwap V3 Swap Router, the payer address indicates who should cover the cost of the swap, whether it's the user initiating the swap or the contract itself.
    }

    /// @inheritdoc IPancakeV3SwapCallback
    // enough explanation given by ChatGPT "StableSwap interface" chat head
    function pancakeV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata _data) external override {
        require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported
        SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));
        (address tokenIn, address tokenOut, uint24 fee) = data.path.decodeFirstPool();
        SmartRouterHelper.verifyCallback(deployer, tokenIn, tokenOut, fee);

        (bool isExactInput, uint256 amountToPay) = amount0Delta > 0
            ? (tokenIn < tokenOut, uint256(amount0Delta))
            : (tokenOut < tokenIn, uint256(amount1Delta));

        if (isExactInput) {
            pay(tokenIn, data.payer, msg.sender, amountToPay);
        } else {
            // either initiate the next swap or pay
            if (data.path.hasMultiplePools()) {
                data.path = data.path.skipToken();
                exactOutputInternal(amountToPay, msg.sender, 0, data);
            } else {
                amountInCached = amountToPay;
                // note that because exact output swaps are executed in reverse order, tokenOut is actually tokenIn
                pay(tokenOut, data.payer, msg.sender, amountToPay);
            }
        }
    }

    // *******************Exact Input Swaps:*******************

    /*
    In summary, these functions cater to different levels of complexity and flexibility in trading. exactInputInternal() is used for straightforward single swaps within a single pool, exactInputSingle() is for multi-step swaps with a single pair of input and output tokens, and exactInput() is for more intricate trading strategies involving multiple tokens and pools in a single transaction
    */

    /// @dev Performs a single exact input swap
    /// @notice `refundETH` should be called at very end of all swaps
    /*
Purpose: This function performs a single exact input swap internally within the contract.
Use Case: It is typically used as a utility function within the contract to execute a specific swap without any additional routing or multiple steps.
Parameters: It takes the amount of tokens to be input (amountIn), the recipient address (recipient), and optionally a price limit as input.
Example: It's used when you want to directly swap a certain amount of token A for token B 
WITHIN A SINGLE POOL without involving multiple pools or routes.
*/
    function exactInputInternal(
        uint256 amountIn,
        address recipient,
        uint160 sqrtPriceLimitX96,
        SwapCallbackData memory data
    ) private returns (uint256 amountOut) {
        // find and replace recipient addresses
        if (recipient == Constants.MSG_SENDER) recipient = msg.sender;
        else if (recipient == Constants.ADDRESS_THIS) recipient = address(this);

        (address tokenIn, address tokenOut, uint24 fee) = data.path.decodeFirstPool();

        bool zeroForOne = tokenIn < tokenOut;

        (int256 amount0, int256 amount1) = SmartRouterHelper.getPool(deployer, tokenIn, tokenOut, fee).swap(
            recipient,
            zeroForOne,
            amountIn.toInt256(),
            sqrtPriceLimitX96 == 0
                ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : sqrtPriceLimitX96,
            abi.encode(data)
        );

        return uint256(-(zeroForOne ? amount1 : amount0));
    }

    /// @inheritdoc IV3SwapRouter
    /*
Purpose: This function is used for executing a series of exact input swaps in a single transaction, possibly involving multiple pools and tokens.
Use Case: It's suitable for COMPLEX TRADES that require routing through multiple pools to achieve the desired output.
Parameters: It takes an ExactInputSingleParams struct as input, which includes details such as the token to be input (tokenIn), the desired token to be received (tokenOut), the recipient address (recipient), and other parameters.
Example: It's used when you want to trade a certain amount of token A for token B, but the trade involves routing 
THRU MULTIPLE POOLS to get the best price.
*/
    function exactInputSingle(
        ExactInputSingleParams memory params
    ) external payable override nonReentrant returns (uint256 amountOut) {
        // use amountIn == Constants.CONTRACT_BALANCE as a flag to swap the entire balance of the contract
        bool hasAlreadyPaid;
        if (params.amountIn == Constants.CONTRACT_BALANCE) {
            hasAlreadyPaid = true;
            params.amountIn = IERC20(params.tokenIn).balanceOf(address(this));
        }

        amountOut = exactInputInternal(
            params.amountIn,
            params.recipient,
            params.sqrtPriceLimitX96,
            SwapCallbackData({
                path: abi.encodePacked(params.tokenIn, params.fee, params.tokenOut),
                payer: hasAlreadyPaid ? address(this) : msg.sender
            })
        );
        require(amountOut >= params.amountOutMinimum);
    }

    /// @inheritdoc IV3SwapRouter
    /*
Purpose: This function is used for executing a sequence of exact input swaps, which may involve multiple tokens and pools, in a single transaction.
Use Case: It's suitable for MORE COMPLEX TRADING STRATEGIES that require a combination of swaps across various pools and tokens.
Parameters: It takes an ExactInputParams struct as input, which includes a path representing the sequence of pools and tokens to traverse.
Example: It's used when you have a 
SPECIFIC TRADING PATH IN MIND that involves swapping token A for token B, then token B for token C, and so on, potentially across different pools.

*/
    function exactInput(
        ExactInputParams memory params
    ) external payable override nonReentrant returns (uint256 amountOut) {
        // use amountIn == Constants.CONTRACT_BALANCE as a flag to swap the entire balance of the contract
        bool hasAlreadyPaid;
        if (params.amountIn == Constants.CONTRACT_BALANCE) {
            hasAlreadyPaid = true;
            (address tokenIn, , ) = params.path.decodeFirstPool();
            params.amountIn = IERC20(tokenIn).balanceOf(address(this));
        }

        address payer = hasAlreadyPaid ? address(this) : msg.sender;

        while (true) {
            bool hasMultiplePools = params.path.hasMultiplePools();

            // the outputs of prior swaps become the inputs to subsequent ones
            params.amountIn = exactInputInternal(
                params.amountIn,
                hasMultiplePools ? address(this) : params.recipient, // for intermediate swaps, this contract custodies
                0,
                SwapCallbackData({
                    path: params.path.getFirstPool(), // only the first pool in the path is necessary
                    payer: payer
                })
            );

            // decide whether to continue or terminate
            if (hasMultiplePools) {
                payer = address(this);
                params.path = params.path.skipToken();
            } else {
                amountOut = params.amountIn;
                break;
            }
        }

        require(amountOut >= params.amountOutMinimum);
    }

    // *******************Exact Output Swaps:*******************

    /*
    In summary, the exactOutput swapping functions mirror the functionality of the exactInput functions but focus on achieving a specified output amount instead of a specified input amount. They are used for more complex trading scenarios that require precise control over the output while considering routing through multiple pools and tokens.
    */

    /// @dev Performs a single exact output swap
    /// @notice `refundETH` should be called at very end of all swaps

    /*
Purpose: Performs a single exact output swap internally within the contract.
Use Case: Useful for executing a specific swap operation that guarantees a specific output amount.
Parameters: Takes the amount of tokens to be received (amountOut), the recipient address (recipient), and optionally a price limit as input.
Example: Used when you want to receive a specific amount of token B and are willing to trade token A for it within a single pool.
*/
    function exactOutputInternal(
        uint256 amountOut,
        address recipient,
        uint160 sqrtPriceLimitX96,
        SwapCallbackData memory data
    ) private returns (uint256 amountIn) {
        // find and replace recipient addresses
        if (recipient == Constants.MSG_SENDER) recipient = msg.sender;
        else if (recipient == Constants.ADDRESS_THIS) recipient = address(this);

        (address tokenOut, address tokenIn, uint24 fee) = data.path.decodeFirstPool();

        bool zeroForOne = tokenIn < tokenOut;

        (int256 amount0Delta, int256 amount1Delta) = SmartRouterHelper.getPool(deployer, tokenIn, tokenOut, fee).swap(
            recipient,
            zeroForOne,
            -amountOut.toInt256(),
            sqrtPriceLimitX96 == 0
                ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : sqrtPriceLimitX96,
            abi.encode(data)
        );

        uint256 amountOutReceived;
        (amountIn, amountOutReceived) = zeroForOne
            ? (uint256(amount0Delta), uint256(-amount1Delta))
            : (uint256(amount1Delta), uint256(-amount0Delta));
        // it's technically possible to not receive the full output amount,
        // so if no price limit has been specified, require this possibility away
        if (sqrtPriceLimitX96 == 0) require(amountOutReceived == amountOut);
    }

    /// @inheritdoc IV3SwapRouter

    /*
Purpose: Executes a series of exact output swaps in a single transaction, possibly involving multiple pools and tokens, with the goal of achieving a desired output amount.
Use Case: Suitable for complex trades that require routing through multiple pools to achieve the desired output while specifying the exact output amount.
Parameters: Takes an ExactOutputSingleParams struct as input, which includes details such as the desired token to be received (tokenOut), the input token (tokenIn), the recipient address (recipient), and other parameters.
Example: Used when you want to receive a specific amount of token B and are willing to trade token A for it while considering routing through multiple pools.
*/
    function exactOutputSingle(
        ExactOutputSingleParams calldata params
    ) external payable override nonReentrant returns (uint256 amountIn) {
        // avoid an SLOAD by using the swap return data
        amountIn = exactOutputInternal(
            params.amountOut,
            params.recipient,
            params.sqrtPriceLimitX96,
            SwapCallbackData({path: abi.encodePacked(params.tokenOut, params.fee, params.tokenIn), payer: msg.sender})
        );

        require(amountIn <= params.amountInMaximum);
        // has to be reset even though we don't use it in the single hop case
        amountInCached = DEFAULT_AMOUNT_IN_CACHED;
    }

    /// @inheritdoc IV3SwapRouter

    /*
Purpose: Executes a sequence of exact output swaps, which may involve multiple tokens and pools, in a single transaction to achieve a specified output amount.
Use Case: Suitable for complex trading strategies where you have a target output amount in mind, and the contract routes through various pools and tokens to achieve it.
Parameters: Takes an ExactOutputParams struct as input, which includes a path representing the sequence of pools and tokens to traverse.
Example: Used when you have a specific trading path in mind that involves receiving a specific amount of token B, then token B for token C, and so on, potentially across different pools.
*/
    function exactOutput(
        ExactOutputParams calldata params
    ) external payable override nonReentrant returns (uint256 amountIn) {
        exactOutputInternal(
            params.amountOut,
            params.recipient,
            0,
            SwapCallbackData({path: params.path, payer: msg.sender})
        );

        amountIn = amountInCached;
        require(amountIn <= params.amountInMaximum);
        amountInCached = DEFAULT_AMOUNT_IN_CACHED;
    }
}

/*
Swap Routing:
The contract handles multi-hop swaps by recursively calling exactInputInternal or exactOutputInternal. It tracks intermediate swaps and ensures that the appropriate tokens are paid for each swap.

Callback Data:
Callback data is encoded and passed to the PancakeSwap V3 pools during swaps. This data contains information about the path, payer, and swap details.

Recipient Address Replacement:
The contract replaces recipient addresses with the appropriate addresses, such as msg.sender or address(this), based on the context of the swap.

Price Limit:
The contract allows users to specify a price limit (sqrtPriceLimitX96) for swaps. This limit helps prevent swaps from executing at unfavorable prices.

Reentrancy Protection:
The contract uses the ReentrancyGuard modifier to protect against reentrant attacks during swap execution.
*/
