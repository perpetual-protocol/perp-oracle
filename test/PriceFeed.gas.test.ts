import { parseEther } from "ethers/lib/utils"
import { ethers, waffle } from "hardhat"
import { BandPriceFeed, ChainlinkPriceFeed, TestAggregatorV3, TestPriceFeed, TestStdReference } from "../typechain"

interface PriceFeedFixture {
    bandPriceFeed: BandPriceFeed
    bandReference: TestStdReference
    baseAsset: string

    // chainlinik
    chainlinkPriceFeed: ChainlinkPriceFeed
    aggregator: TestAggregatorV3
}

async function priceFeedFixture(): Promise<PriceFeedFixture> {
    // band protocol
    const testStdReferenceFactory = await ethers.getContractFactory("TestStdReference")
    const testStdReference = await testStdReferenceFactory.deploy()

    const baseAsset = "ETH"
    const bandPriceFeedFactory = await ethers.getContractFactory("BandPriceFeed")
    const bandPriceFeed = (await bandPriceFeedFactory.deploy(testStdReference.address, baseAsset)) as BandPriceFeed

    // chainlink
    const testAggregatorFactory = await ethers.getContractFactory("TestAggregatorV3")
    const testAggregator = await testAggregatorFactory.deploy()

    const chainlinkPriceFeedFactory = await ethers.getContractFactory("ChainlinkPriceFeed")
    const chainlinkPriceFeed = (await chainlinkPriceFeedFactory.deploy(testAggregator.address)) as ChainlinkPriceFeed

    return { bandPriceFeed, bandReference: testStdReference, baseAsset, chainlinkPriceFeed, aggregator: testAggregator }
}

describe.skip("Price feed gas test", () => {
    const [admin] = waffle.provider.getWallets()
    const loadFixture: ReturnType<typeof waffle.createFixtureLoader> = waffle.createFixtureLoader([admin])
    let bandPriceFeed: BandPriceFeed
    let bandReference: TestStdReference
    let chainlinkPriceFeed: ChainlinkPriceFeed
    let aggregator: TestAggregatorV3
    let currentTime: number
    let testPriceFeed: TestPriceFeed
    let beginPrice = 400
    let round: number

    async function updatePrice(price: number, forward: boolean = true): Promise<void> {
        await bandReference.setReferenceData({
            rate: parseEther(price.toString()),
            lastUpdatedBase: currentTime,
            lastUpdatedQuote: currentTime,
        })
        await bandPriceFeed.update()

        await aggregator.setRoundData(round, parseEther(price.toString()), currentTime, currentTime, round)

        if (forward) {
            currentTime += 15
            await ethers.provider.send("evm_setNextBlockTimestamp", [currentTime])
            await ethers.provider.send("evm_mine", [])
        }
    }

    before(async () => {
        const _fixture = await loadFixture(priceFeedFixture)
        bandReference = _fixture.bandReference
        bandPriceFeed = _fixture.bandPriceFeed
        chainlinkPriceFeed = _fixture.chainlinkPriceFeed
        aggregator = _fixture.aggregator
        round = 0

        const TestPriceFeedFactory = await ethers.getContractFactory("TestPriceFeed")
        testPriceFeed = (await TestPriceFeedFactory.deploy(
            chainlinkPriceFeed.address,
            bandPriceFeed.address,
        )) as TestPriceFeed

        currentTime = (await waffle.provider.getBlock("latest")).timestamp
        for (let i = 1; i < 255; i++) {
            round = i
            await updatePrice(beginPrice + i)
        }
    })

    describe("2 loops", () => {
        it("band protocol ", async () => {
            await testPriceFeed.fetchBandProtocolPrice(15 * 2)
        })

        it("chainlink", async () => {
            await testPriceFeed.fetchChainlinkPrice(15 * 2)
        })
    })

    describe("100 loops", () => {
        it("band protocol ", async () => {
            await testPriceFeed.fetchBandProtocolPrice(15 * 100)
        })

        it("chainlink", async () => {
            await testPriceFeed.fetchChainlinkPrice(15 * 100)
        })
    })

    describe("200 loops", () => {
        it("band protocol ", async () => {
            await testPriceFeed.fetchBandProtocolPrice(15 * 200)
        })

        it("chainlink", async () => {
            await testPriceFeed.fetchChainlinkPrice(15 * 200)
        })
    })
})
