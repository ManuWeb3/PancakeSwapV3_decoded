// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

/// @title Router token swapping functionality
/// @notice Functions for swapping tokens via Pancake Stable Swap
interface IStableSwapRouter {
    /** 
     * @param flag token amount in a stable swap pool. 2 for 2pool, 3 for 3pool    
     * Purpose: This function is used for swapping tokens by specifying the exact input amount (amountIn) and the minimum acceptable output amount (amountOutMin). It allows users to swap one or more tokens in a stable swap pool.
Parameters:
path: An array of token addresses that represent the token path for the swap. It specifies the input and output tokens in the order of the swap.
flag: An array specifying the token amount in the stable swap pool (e.g., 2 for a 2pool or 3 for a 3pool).
amountIn: The exact amount of input tokens to be swapped.
amountOutMin: The minimum acceptable amount of output tokens. If the actual output amount is less than this value, the transaction will revert.
to: The address to which the swapped tokens will be sent.
Returns: The actual amount of output tokens received after the swap.
     */
    function exactInputStableSwap(
        address[] calldata path,
        uint256[] calldata flag, // an array that specifies the token amount in the stable swap pool
        uint256 amountIn,
        uint256 amountOutMin,
        address to
    ) external payable returns (uint256 amountOut);

    /**
     * @param flag token amount in a stable swap pool. 2 for 2pool, 3 for 3pool
     * Purpose: This function is used for swapping tokens by specifying the exact output amount (amountOut) and the maximum acceptable input amount (amountInMax). It allows users to swap one or more tokens in a stable swap pool while ensuring a specific output amount.
Parameters:
path: An array of token addresses that represent the token path for the swap. It specifies the input and output tokens in the order of the swap.
flag: An array specifying the token amount in the stable swap pool (e.g., 2 for a 2pool or 3 for a 3pool).
amountOut: The exact amount of output tokens to be received.
amountInMax: The maximum acceptable amount of input tokens. If the actual input amount exceeds this value, the transaction will revert.
to: The address to which the swapped tokens will be sent.
Returns: The actual amount of input tokens used for the swap.
     */
    function exactOutputStableSwap(
        address[] calldata path,
        uint256[] calldata flag, // an array that specifies the token amount in the stable swap pool
        uint256 amountOut,
        uint256 amountInMax,
        address to
    ) external payable returns (uint256 amountIn);
}

/*
The "flag" Parameter:

The "flag" parameter is an array that specifies the token amount in the stable swap pool for each token involved in the swap. Each element of the "flag" array corresponds to a token in the path array, and it determines which stable swap pool is used for the trade.

The values in the "flag" array typically correspond to the number of assets in the stable swap pool. For example:

If the "flag" array is [2], it indicates that you are trading in a 2-token pool.
If the "flag" array is [3, 4], it indicates that you are trading in a pool with 3 tokens and another pool with 4 tokens.
The "flag" values help the contract understand which stable swap pool(s) to access to perform the swap accurately.
*/
