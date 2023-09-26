// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

interface IStableSwap {
    // solium-disable-next-line mixedcase
    /*
    Purpose: This function is used to calculate the expected output amount (dy) when swapping or trading between two different assets or tokens.
    Parameters:
    i: The index of the source token (input token).
    j: The index of the destination token (output token).
    dx: The amount of the source token to be swapped.
    Returns: The expected output amount (dy) after the swap.
    */
    function get_dy(uint256 i, uint256 j, uint256 dx) external view returns (uint256 dy);

    // solium-disable-next-line mixedcase
    /*
    Purpose: This function is used to execute a swap between two different tokens. 
    It takes the source token (i), destination token (j), 
    the amount of source tokens to be swapped (dx), 
    and a minimum expected output amount (minDy). 
    If the actual output amount is greater than or equal to minDy, 
    the swap is executed; otherwise, it reverts the transaction. 
    Parameters:
    i: The index of the source token (input token).
    j: The index of the destination token (output token).
    dx: The amount of the source token to be swapped.
    minDy: The minimum expected output amount.
    Note: It is marked as payable, indicating that it might involve sending Ether (BNB) along with the transaction.
    */
    function exchange(uint256 i, uint256 j, uint256 dx, uint256 minDy) external payable;

    // solium-disable-next-line mixedcase
    /*
    Purpose: This function is used to retrieve the address of a token at a given index. It allows you to identify which token corresponds to a specific index for use in other functions.
    Parameters:
    i: The index of the token.
    Returns: The address of the token at the specified index.
    */
    function coins(uint256 i) external view returns (address);

    // solium-disable-next-line mixedcase
    /*
    Purpose: This function is used to retrieve the balance of a specific token in the contract.
    Parameters:
    i: The index of the token.
    Returns: The balance of the token at the specified index.
    */
    function balances(uint256 i) external view returns (uint256);

    // solium-disable-next-line mixedcase
    /*
    Purpose: This function is used to retrieve a parameter related to the specific automated market maker (AMM) or stable swap pool. The meaning of this parameter would depend on the specific implementation of the AMM.
    */
    function A() external view returns (uint256);

    // solium-disable-next-line mixedcase
    /*
    Purpose: This function is used to retrieve the fee rate associated with the stable swap pool or AMM. It represents the trading fee percentage that is charged on swaps within the pool.
    */
    function fee() external view returns (uint256);
}
