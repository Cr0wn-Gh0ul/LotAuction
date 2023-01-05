interface IAuction {
  function addBid (  ) external;
  function addressToAmount ( address ) external view returns ( uint256 );
  function amountToAddress ( uint256 ) external view returns ( address );
  function checkActiveAuction (  ) external view;
  function collectPrizes (  ) external;
  function endTime (  ) external view returns ( uint256 );
  function increaseBid (  ) external;
  function maxWinningBids (  ) external view returns ( uint256 );
  function newValidBid ( uint256 value_ ) external view returns ( uint256 );
  function prizesPerAddress (  ) external view returns ( uint256 );
  function removeBid (  ) external;
  function settleAuction (  ) external;
  function settled (  ) external view returns ( bool );
  function startTime (  ) external view returns ( uint256 );
  function totalPrizes (  ) external view returns ( uint256 );
  function validateBid ( uint256 amount_, address addr_ ) external view returns ( uint256 );
  function winningBidsPlaced (  ) external view returns ( uint256 );
}
