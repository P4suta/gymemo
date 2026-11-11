import { defineConfig } from "@playwright/test";

export function websiteTarget(value: string | undefined): {
	production: boolean;
	baseURL: string;
} {
	if (value === undefined) {
		return { production: false, baseURL: "http://127.0.0.1:4174" };
	}
	if (value === "production") {
		return { production: true, baseURL: "https://gymemo.yasunobu.dev" };
	}
	throw new Error("GYMEMO_WEBSITE_TARGET must be unset or production");
}

const { production, baseURL } = websiteTarget(
	process.env.GYMEMO_WEBSITE_TARGET,
);

export default defineConfig({
	testDir: "./e2e",
	fullyParallel: true,
	forbidOnly: true,
	workers: 2,
	retries: 0,
	maxFailures: 1,
	timeout: 30_000,
	globalTimeout: 600_000,
	reporter: [["list"], ["html", { open: "never" }]],
	use: {
		baseURL,
		browserName: "chromium",
		channel: "chrome",
		headless: true,
		trace: "retain-on-failure",
		screenshot: "only-on-failure",
	},
	projects: [
		{
			name: "narrow-light",
			use: { viewport: { width: 320, height: 960 }, colorScheme: "light" },
		},
		{
			name: "narrow-dark",
			use: { viewport: { width: 320, height: 960 }, colorScheme: "dark" },
		},
		{
			name: "wide-light",
			use: { viewport: { width: 1280, height: 960 }, colorScheme: "light" },
		},
		{
			name: "wide-dark",
			use: { viewport: { width: 1280, height: 960 }, colorScheme: "dark" },
		},
		{
			name: "intermediate-contrast",
			use: { viewport: { width: 640, height: 480 }, forcedColors: "active" },
		},
	],
	...(production
		? {}
		: {
				webServer: {
					command:
						"npm exec --offline -- wrangler dev --local --ip 127.0.0.1 --port 4174",
					url: baseURL,
					reuseExistingServer: false,
					gracefulShutdown: { signal: "SIGTERM", timeout: 1000 },
				},
			}),
});
