const { networks } = require("../../networks");

task("deploy-core", "Deploys the DropifyCore contract")
  .addOptionalParam(
    "verify",
    "Set to true to verify contract",
    false,
    types.boolean
  )
  .setAction(async (taskArgs) => {
    console.log(`Deploying DropifyCore contract to ${network.name}`);

    console.log("\n__Compiling Contracts__");
    await run("compile");

    const dropifyCoreContractFactory = await ethers.getContractFactory(
      "DropifyCore"
    );

    const args = [
      networks[network.name].chainId,
      networks[network.name].vaultAddress,
      networks[network.name].ccipRouter,
      "0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93",
      "0x4200000000000000000000000000000000000021",
      "0xa47b91299da9a0bd968e0030568703a00ad0d851bd9c32efb98a53e39750ed42",
      "0x82ba92089cfdf9cd4340c24b35356aabf92e5bac94f264af89e060cb4896bbcd",
      "0x42FF98C4E85212a5D31358ACbFe76a621b50fC02",
      "app_staging_e18da2aa6edc21af57c170b0abfef1d6",
      "unique-human-airdrop",
    ];

    const dropifyCoreContract = await dropifyCoreContractFactory.deploy(args);

    console.log(
      `\nWaiting ${
        networks[network.name].confirmations
      } blocks for transaction ${
        dropifyCoreContract.deployTransaction.hash
      } to be confirmed...`
    );

    await dropifyCoreContract.deployTransaction.wait(
      networks[network.name].confirmations
    );

    console.log(
      "\nDeployed DropifyCore contract to:",
      dropifyCoreContract.address
    );

    if (network.name === "localFunctionsTestnet") {
      return;
    }

    const verifyContract = taskArgs.verify;
    if (
      network.name !== "localFunctionsTestnet" &&
      verifyContract &&
      !!networks[network.name].verifyApiKey &&
      networks[network.name].verifyApiKey !== "UNSET"
    ) {
      try {
        console.log("\nVerifying contract...");
        await run("verify:verify", {
          address: dropifyCoreContract.address,
          constructorArguments: [args],
        });
        console.log("Contract verified");
      } catch (error) {
        if (!error.message.includes("Already Verified")) {
          console.log(
            "Error verifying contract.  Ensure you are waiting for enough confirmation blocks, delete the build folder and try again."
          );
          console.log(error);
        } else {
          console.log("Contract already verified");
        }
      }
    } else if (verifyContract && network.name !== "localFunctionsTestnet") {
      console.log(
        "\nPOLYGONSCAN_API_KEY, ETHERSCAN_API_KEY or FUJI_SNOWTRACE_API_KEY is missing. Skipping contract verification..."
      );
    }

    console.log(
      `\n DropifyCore contract deployed to ${dropifyCoreContract.address} on ${network.name}`
    );
  });
