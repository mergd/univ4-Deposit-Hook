/// Deposit hook for Uniswap v4

Creates a very gas efficient token called Uni20 that is used as a receipt token within Uniswap – however, the trick is that as the token is swapped out by the swapper, the underlying gets sent to them.

There's probably a cleaner way to do it, but this is a neat idea as it allows for all the vault assets to be deposited instead of only a portion being deposited as we see with Balancer or Aloe.

This contract also assumes 0 deposit and withdraw slippage with the underlying ERC4626 vault and doesn't check for slippage either.
