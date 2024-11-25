import { setup } from "../lib";

const deployer = await setup("mainnet");

const [extensionPO, extensionCL] = await deployer.deployExtensions(
  deployer.config.protocol.singleton!,
  deployer.config.protocol.pragma,
);

console.log("ExtensionPO: ", extensionPO.address);
console.log("ExtensionCL: ", extensionCL.address);
