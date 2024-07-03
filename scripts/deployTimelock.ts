import { CallData } from "starknet";
import { setup } from "../lib";

const deployer = await setup(process.env.NETWORK);

const [timelock, calls] = await deployer.deferContract(
  "Timelock",
  CallData.compile({ owner: deployer.creator.address, config: { delay: 604800, window: 604800 } }),
);

let response = await deployer.execute([...calls]);
await deployer.waitForTransaction(response.transaction_hash);

console.log("Deployed:", { timelock: timelock.address });
