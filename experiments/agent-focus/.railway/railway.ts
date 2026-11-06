import { defineRailway, project, service, volume } from "railway/iac";

export default defineRailway(() => {
  const relayVolume = volume("relay-volume", { alerts: { usage: { "100": {}, "80": {}, "95": {} } }, allowOnlineResize: true, region: "iad", sizeMB: 500 });
  const relay = service("relay", {
    build: { buildEnvironment: "V3", builder: "DOCKERFILE", dockerfilePath: "Dockerfile" },
    deploy: {
      sleepApplication: false,
      restartPolicyType: "ALWAYS",
      healthcheckPath: "/healthz",
      healthcheckTimeout: 60,
    },
    replicas: { "iad": 1 },
    volumeMounts: { "/data": relayVolume },
  });

  return project("docard-focus", {
    variables: { managed: false },
    resources: [relay, relayVolume],
  });
});
