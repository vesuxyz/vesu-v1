import { logAddresses, setup } from "../lib";

const deployer = await setup(process.env.NETWORK);

const [contracts, response] = await deployer.deployEnv();

logAddresses("Deployed:", contracts);

console.log("Deployment tx:", response.transaction_hash);
await deployer.waitForTransaction(response.transaction_hash);
