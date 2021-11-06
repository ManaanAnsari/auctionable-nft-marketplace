from brownie import NFTMarket, NFT, accounts


def deploy():
    from_det = {'from': accounts[0]}
    # deploy market
    market = NFTMarket.deploy(from_det)
    print("deployed market")
    # deploy nft 
    nft = NFT.deploy( market.address, from_det)
    print("deployed nft")
    

def main():
    deploy()