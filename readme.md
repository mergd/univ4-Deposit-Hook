/// Deposit hook for Uniswap v4

Creates a mock token called Uni20 that is used as a receipt token within Uniswap – however, the trick is that as the token is swapped out by the swapper, the underlying gets sent to them.

There's probably a cleaner way to do it, but this is a neat idea as it allows for all the vault assets to be deposited instead of only a portion being deposited as we see with Balancer or Aloe.
