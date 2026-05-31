// Remotion config. The entry point is passed explicitly on the CLI
// (src/index.tsx), so this only tunes rendering defaults.
import { Config } from "@remotion/cli/config";

Config.setVideoImageFormat("jpeg");
Config.setOverwriteOutput(true);
Config.setConcurrency(null); // auto: scale to available cores
