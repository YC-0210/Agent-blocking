import { defineRailway, project, service, volume } from "railway/iac";

export default defineRailway(() => {
  const relayVolume = volume("relay-volume", { alerts: { usage: { "100": {}, "80": {}, "95": {} } }, allowOnlineResize: true, region: "iad", sizeMB: 500 });
  const productionVolume = volume("production-apns-volume", { alerts: { usage: { "100": {}, "80": {}, "95": {} } }, allowOnlineResize: true, region: "iad", sizeMB: 500 });
  const relayService = (name: string, databaseVolume: typeof relayVolume) => service(name, {
    build: { buildEnvironment: "V3", builder: "DOCKERFILE", dockerfilePath: "Dockerfile" },
    deploy: {
      healthcheckPath: "/healthz",
      healthcheckTimeout: 60,
      restartPolicyType: "ALWAYS",
      sleepApplication: false,
    },
    replicas: { "iad": 1 },
    volumeMounts: { "/data": databaseVolume },
  });

  return project("agent-blocking", {
    variables: { managed: false },
    resources: [
      relayService("relay", relayVolume), relayVolume,
      relayService("relay-production-apns", productionVolume), productionVolume,
    ],
  });
});
