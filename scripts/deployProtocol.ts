import { logAddresses, setup } from "../lib";

const deployer = await setup();

const [contracts, response] = await deployer.deployProtocol(deployer.config.protocol.oracle!);

logAddresses("Deployed:", contracts);

console.log("Deployment tx:", response.transaction_hash);
await deployer.waitForTransaction(response.transaction_hash);
