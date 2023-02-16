const { network, ethers } = require("hardhat")
const { developmentChains } = require("../helper-hardhat-config")
const { verify } = require("../utils/verify")

module.exports = async function ({ getNamedAccounts, deployments }) {
    const { deploy, log } = deployments
    const { deployer } = await getNamedAccounts()
    log("------------------------")

    let ensAddress
    if (developmentChains.includes(network.name)) {
        const ens = await ethers.getContract("MockENS")
        ensAddress = ens.address
    } else {
        ensAddress = "0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85"
    }

    const args = [ensAddress]
    const rentENS = await deploy("RentENS", {
        from: deployer,
        args: args,
        log: true,
        waitConfirmations: network.config.blockConfirmations || 1,
    })

    if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
        log("Verifying...")
        await verify(rentENS.address, args)
    }
    log("------------------------")
}

module.exports.tags = ["all", "rentens", "main"]
