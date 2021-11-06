// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.3;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";



contract NFTMarket is ReentrancyGuard {
  using Counters for Counters.Counter;
  Counters.Counter private _auctionIds;
  Counters.Counter private _auctionsCompleted;
  Counters.Counter private _auctionsCanceled;
  Counters.Counter private _auctionsPaused;

  address payable admin;
  uint256 marketFee = 0.025 ether;

  constructor() {
    admin = payable(msg.sender);
  }

  struct Auction {
    uint auctionId;
    uint256 blockDeadline;
    address nftContract;
    uint256 tokenId;
    address payable auctionCreator;
    address payable itemOwner;
    uint256 startPrice;
    uint256 buyNowPrice;
    bool active;
    bool finalized;
    bool canceled;
    bool adminPause;
  }

  // Bid struct to hold bidder and amount
  struct Bid {
    address payable from;
    uint256 amount;
  }

  mapping(uint256 => Auction) private idToAuction;  // auctionId => Auction obj
  mapping(uint256 => Bid[]) public auctionBids;     // auctionId => bids



  function createAuction(
    address nftContract,
    uint256 tokenId,
    uint256 _startPrice,
    uint256 _buyNowPrice,
    uint _blockDeadline

  ) public payable nonReentrant {
    require(_startPrice > 0 || _buyNowPrice >0 , "start/buynow Price must be at least 1 wei");
    require(msg.value == marketFee, "Price must be equal to listing price");
    require(_blockDeadline > block.timestamp || _buyNowPrice >0  ," deadline should be greater than now");
    if (_blockDeadline <block.timestamp){
      _blockDeadline = 0;
    }
    _auctionIds.increment();
    uint256 auctionId = _auctionIds.current();
  
    idToAuction[auctionId] =  Auction(
      auctionId,
      _blockDeadline,
      nftContract,
      tokenId,
      payable(msg.sender),
      payable(address(0)),
      _startPrice,
      _buyNowPrice,
      true,
      false,
      false,
      false
    );

    IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);

  }

  function cancelAuction(
    uint256 _auctionId
  ) public allowedByAdmin(_auctionId) {
    require(idToAuction[_auctionId].auctionCreator == msg.sender || admin == msg.sender , "only contract creator or admin can cancel auction");
    require( block.timestamp < idToAuction[_auctionId].blockDeadline || idToAuction[_auctionId].blockDeadline == 0 ,"Auction time ended!" );
    idToAuction[_auctionId].canceled = true;
    _auctionsCanceled.increment();
    Bid[] memory all_bids = auctionBids[_auctionId];
    if(all_bids.length > 0){
      Bid memory lastBid = all_bids[all_bids.length - 1];
      if(lastBid.amount > 0){
        if(!lastBid.from.send(lastBid.amount)) {
            revert();
        }  
      }  
    }
  }

  function reList(
    address nftContract,
    uint256 _auctionId,
    uint256 _startPrice,
    uint256 _buyNowPrice,
    uint _blockDeadline
    ) public payable nonReentrant allowedByAdmin(_auctionId) {

    require(_startPrice > 0 || _buyNowPrice >0 , "start/buynow Price must be at least 1 wei");
    require(msg.value == marketFee, "Price must be equal to listing price");
    require(_blockDeadline > block.timestamp || _buyNowPrice >0 ," deadline should be greater than now or should have buynow price for simple listing ");
    require(idToAuction[_auctionId].itemOwner == msg.sender , "you dont own this!");
    require(idToAuction[_auctionId].active == false, "Trading on your NFT Token is temporarily paused");
    
    if (_blockDeadline <block.timestamp){
      _blockDeadline = 0;
    }

    idToAuction[_auctionId].startPrice = _startPrice;
    idToAuction[_auctionId].buyNowPrice = _buyNowPrice;
    idToAuction[_auctionId].blockDeadline = _blockDeadline;
    idToAuction[_auctionId].auctionCreator = payable(msg.sender);
    idToAuction[_auctionId].itemOwner = payable(address(0));
    idToAuction[_auctionId].active = true;
    idToAuction[_auctionId].finalized = false;
    IERC721(nftContract).transferFrom(msg.sender,address(this),idToAuction[_auctionId].tokenId);
    _auctionsCompleted.decrement();
  }


  function bidOnAuction(uint _auctionId) public payable allowedByAdmin(_auctionId) {
    require(idToAuction[_auctionId].blockDeadline >0 , "not for auction!" );
    require(idToAuction[_auctionId].finalized == false, "Auction ended!");
    require(idToAuction[_auctionId].active == true, "Auction Inactive!");
    require(block.timestamp < idToAuction[_auctionId].blockDeadline, "Auction timesup!");
    require(idToAuction[_auctionId].auctionCreator != msg.sender, "creator and bidder cannot be same!");
    require( msg.value > 0, "bid is less than 0");
    require(msg.value  < idToAuction[_auctionId].buyNowPrice , "Buy now price is less then bid amount");
    
    
    uint256 ethAmountSent = msg.value;
    // owner can't bid on their auctions
    Auction memory myAuction = idToAuction[_auctionId];


    uint bidsLength = auctionBids[_auctionId].length;
    uint256 tempAmount = myAuction.startPrice;
    Bid memory lastBid;

    // there are previous bids
    if( bidsLength > 0 ) {
        lastBid = auctionBids[_auctionId][bidsLength - 1];
        tempAmount = lastBid.amount;
    }

    // check if amound is greater than previous amount
    require(ethAmountSent > tempAmount, "bid amt should be greater than last bid");

    // refund the last bidder
    if( bidsLength > 0 ) {
        if(!lastBid.from.send(lastBid.amount)) {
            revert();
        }  
    }

    // insert bid 
    Bid memory newBid;
    newBid.from = payable(msg.sender);
    newBid.amount = ethAmountSent;
    auctionBids[_auctionId].push(newBid);
  }

  function finalizeAuction(address nftContract , uint _auctionId) public allowedByAdmin(_auctionId) {
    Auction memory myAuction = idToAuction[_auctionId];
    require( myAuction.blockDeadline > 0 ,"not for auction!" );
    uint bidsLength = auctionBids[_auctionId].length;
    // 1. if auction not ended just revert
    require( block.timestamp > myAuction.blockDeadline,"Time still left" );
    // if there are no bids cancel
    if(bidsLength == 0) {
        // cancelAuction(_auctionId);
        myAuction.finalized = true;
    }else{
        // 2. the money goes to the auction owner
        Bid memory lastBid = auctionBids[_auctionId][bidsLength - 1];

        myAuction.auctionCreator.transfer(lastBid.amount);
        IERC721(nftContract).transferFrom(address(this), lastBid.from, myAuction.tokenId);
        myAuction.itemOwner = payable(lastBid.from);
        myAuction.finalized = true;
        myAuction.active = false;
        idToAuction[_auctionId] = myAuction;
        _auctionsCompleted.increment();
        // todo charge fee
      }
    }


  function createSale(
    address nftContract,
    uint256 _auctionId
    ) public payable nonReentrant  allowedByAdmin(_auctionId){
    
    uint _buyNowPrice = idToAuction[_auctionId].buyNowPrice;

    require(_buyNowPrice > 0, "Acution BuyNow not available!");
    require(idToAuction[_auctionId].finalized == false, "Auction ended!");
    require(idToAuction[_auctionId].active == true, "Auction Inactive!");
    require(idToAuction[_auctionId].auctionCreator != msg.sender, "creator and buyer cannot be same!");
    require( msg.value == _buyNowPrice, "value is not equal to BuyNow price!");

    uint tokenId = idToAuction[_auctionId].tokenId;

    idToAuction[_auctionId].auctionCreator.transfer(msg.value);
    IERC721(nftContract).transferFrom(address(this), msg.sender, tokenId);
    idToAuction[_auctionId].itemOwner = payable(msg.sender);
    idToAuction[_auctionId].finalized = true;
    idToAuction[_auctionId].active = false;
    _auctionsCompleted.increment();
    payable(admin).transfer(marketFee);

  }

  // update price (only seller can update it) 
  function updateBuyNowPrice(uint256 _auctionId, uint256 _price) allowedByAdmin(_auctionId) public{
    require(idToAuction[_auctionId].auctionCreator == msg.sender, "Not the owner!");
    require(idToAuction[_auctionId].active == true, "Auction is not active");
    require(_price > 0, "Price cannot be zero");
    Bid[] memory all_bids = auctionBids[_auctionId];
    
    if(all_bids.length>0){
      Bid memory lastBid = all_bids[all_bids.length - 1];
      require(_price > lastBid.amount, "Price cannot be less than latest bid amount");  
    }
    idToAuction[_auctionId].buyNowPrice = _price;
  }

  // temp delisting in case of report 
  function activate(uint256 _auctionId) public  allowedByAdmin(_auctionId) {
    require(idToAuction[_auctionId].auctionCreator == msg.sender, "Not the owner!");
    idToAuction[_auctionId].active = true;
  }

  function deactivate(uint256 _auctionId) public allowedByAdmin(_auctionId) {
    require(idToAuction[_auctionId].auctionCreator == msg.sender, "Not the owner!");
    idToAuction[_auctionId].active = false;
  }

  function AdminPause(uint256 _auctionId) public onlyAdmin {
    idToAuction[_auctionId].adminPause = true;
    _auctionsPaused.increment();
  }

  function AdminUnPause(uint256 _auctionId) public onlyAdmin{
    idToAuction[_auctionId].adminPause = false;
    _auctionsPaused.decrement();
  }

  // all views 
  // todo: add break statements
  /* Returns all unsold market items */
  function fetchAuctions() public view returns (Auction[] memory) {
    uint auctionCount = _auctionIds.current();
    uint activeAuctionsCount = _auctionIds.current() - _auctionsCompleted.current() - _auctionsCanceled.current() - _auctionsPaused.current();
    uint currentIndex = 0;

    Auction[] memory auctions = new Auction[](activeAuctionsCount);
    for (uint i = 0; i < auctionCount; i++) {
      if (idToAuction[i + 1].finalized == false && idToAuction[i + 1].active == true && idToAuction[i + 1].canceled == false && idToAuction[i + 1].adminPause == false ) {
        uint currentId = i + 1;
        Auction storage currentItem = idToAuction[currentId];
        auctions[currentIndex] = currentItem;
        currentIndex += 1;
      }
    }
    return auctions;
  }

  function fetchPurchasedNFTs() public view returns (Auction[] memory) {
    uint totalAuctionCount = _auctionIds.current();
    uint auctionCount = 0;
    uint currentIndex = 0;

    for (uint i = 0; i < totalAuctionCount; i++) {
      if (idToAuction[i + 1].itemOwner == msg.sender) {
        auctionCount += 1;
      }
    }

    Auction[] memory auctions = new Auction[](auctionCount);
    for (uint i = 0; i < totalAuctionCount; i++) {
      if (idToAuction[i + 1].itemOwner == msg.sender) {
        uint currentId = i + 1;
        Auction storage currentAuction = idToAuction[currentId];
        auctions[currentIndex] = currentAuction;
        currentIndex += 1;
      }
    }
    return auctions;
  }

  /* Returns only items a user has created */
  function fetchAuctionsCreated() public view returns (Auction[] memory) {
    uint totalAuctionCount = _auctionIds.current();
    uint auctionCount = 0;
    uint currentIndex = 0;

    for (uint i = 0; i < totalAuctionCount; i++) {
      if (idToAuction[i + 1].auctionCreator == msg.sender) {
        auctionCount += 1;
      }
    }

    Auction[] memory auctions = new Auction[](auctionCount);
    for (uint i = 0; i < totalAuctionCount; i++) {
      if (idToAuction[i + 1].auctionCreator == msg.sender) {
        uint currentId = i + 1;
        Auction storage currentAuction = idToAuction[currentId];
        auctions[currentIndex] = currentAuction;
        currentIndex += 1;
      }
    }
    return auctions;
  }

  /* Returns the listing price of the contract */
  function getMarketFee() public view returns (uint256) {
    return marketFee;
  }

  /* Returns the listing price of the contract */
  function setListingFee(uint256 _marketFee) public onlyAdmin{
    marketFee = _marketFee;
  }
  
  modifier onlyAdmin() {
    require(admin == msg.sender, "caller is not the Admin");
    _;
  }

  modifier allowedByAdmin(uint256 _auctionid) {
    require(idToAuction[_auctionid].adminPause == false, "Trading on your NFT Token is temporarily paused");
    require(idToAuction[_auctionid].canceled == false, "auction has been canceled!");
    _;
  }
}


