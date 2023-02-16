const { assert, expect } = require("chai")
const { network, deployments, ethers } = require("hardhat")
const { developmentChains } = require("../../helper-hardhat-config")
const fs = require("fs")

!developmentChains.includes(network.name)
    ? describe.skip
    : describe("Rent ENS Unit Tests", function () {
          let rentENS, deployer

          beforeEach(async () => {
              accounts = await ethers.getSigners()
              deployer = accounts[0]
              player = accounts[1]
              await deployments.fixture(["all"])
              rentENS = await ethers.getContract("RentENS")
              ens = await ethers.getContract("MockENS")
              await ens.mint(1)
              await ens.mint(2)
              await ens.mint(3)
              await ens.setApprovalForAll(rentENS.address, true)
          })

          describe("Construtor", () => {
              it("Initilizes the NFT Correctly.", async () => {
                  const name = await rentENS.name()
                  const symbol = await rentENS.symbol()
                  assert.equal(name, "RentENS")
                  assert.equal(symbol, "RENS")
              })
              it("Initilizes the Royalties Correctly.", async () => {
                  const response = await rentENS.royaltyInfo(0, ethers.utils.parseEther("1"))
                  const receiver = response[0].toString()
                  const fee = response[1].toString()
                  assert.equal(receiver, deployer.address)
                  assert.equal(fee, ethers.utils.parseEther("0.05").toString())
              })
          })
          describe("createListing", () => {
              it("Emits an event", async () => {
                  await expect(
                      rentENS.createListing(1, [3600 * 24, ethers.utils.parseEther("0.1"), true])
                  ).to.emit(rentENS, "ListingCreated")
              })
              it("Reverts if not owner of ENS name", async () => {
                  const playerConnectedRentENS = rentENS.connect(player)
                  await expect(
                      playerConnectedRentENS.createListing(1, [
                          3600 * 24,
                          ethers.utils.parseEther("52.159"),
                          true,
                      ])
                  ).to.be.revertedWith("RentENS__MustBeEnsOwner")
              })
              it("Reverts if rented out for longer than registered", async () => {
                  await expect(
                      rentENS.createListing(1, [
                          3600 * 24 * 366,
                          ethers.utils.parseEther("0.148"),
                          true,
                      ])
                  ).to.be.revertedWith("RentENS__RentalPeriodLongerThanRegistration")
              })
              it("Cancels Extensions if they are acrive", async () => {})
          })
          describe("cancelListing", () => {
              it("Emits an event", async () => {
                  await rentENS.createListing(1, [3600 * 24, ethers.utils.parseEther("0.1"), true])
                  await expect(rentENS.cancelListing(1)).to.emit(rentENS, "ListingCanceled")
              })
          })
          describe("rent", () => {
              it("Reverts if current ENS owner is not the same as the one who created the listing", async () => {})
              it("Reverts if not enough ether is sent", async () => {})
              it("Pays the owner of the ENS name and pays the fees", async () => {})
              it("Reverts if listing is not active", async () => {})
              it("Reverts if renting period would be longer than ENS is registered for", async () => {})
              it("Reverts if renting time is lower than current block timestamp", async () => {})
              it("Emits an event", async () => {})
              it("Takes control of the ENS name", async () => {})
              it("Mints an NFT to renter", async () => {})
          })
          describe("createExtensionOffer", () => {})
          describe("cancelExtensionOffer", () => {})
          describe("acceptExtensionOffer", () => {})
          describe("regainENS", () => {})
          describe("regainControlAsRenter", () => {})
          describe("setFee", () => {
              it("Updates the Royalties Correctly.", async () => {
                  await rentENS.setFee(player.address, 350)
                  const response = await rentENS.royaltyInfo(0, ethers.utils.parseEther("1"))
                  const receiver = response[0].toString()
                  const fee = response[1].toString()
                  assert.equal(receiver, player.address)
                  assert.equal(fee, ethers.utils.parseEther("0.035").toString())
              })
              it("Reverts if not contract owner", async () => {
                  const playerConnectedRentENS = rentENS.connect(player)
                  await expect(playerConnectedRentENS.setFee(player.address, 350)).to.be.reverted
              })
              it("Reverts if Fee is above 5%", async () => {
                  await expect(rentENS.setFee(player.address, 501)).to.be.revertedWith(
                      "RentENS__FeeTooHigh"
                  )
              })
          })
          describe("_afterTokenTransfer", () => {})
      })

/*




*/
