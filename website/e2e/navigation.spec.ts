import AxeBuilder from "@axe-core/playwright";
import {
	expect,
	type Locator,
	type Page,
	type Route,
	test,
} from "@playwright/test";

const locales = [
	{ language: "ja", path: "/", name: "日本語" },
	{ language: "en", path: "/en/", name: "English" },
	{ language: "zh-Hans", path: "/zh-Hans/", name: "简体中文" },
	{ language: "zh-Hant", path: "/zh-Hant/", name: "繁體中文" },
] as const;
const contents = ["", "support/", "privacy/"] as const;

function headerLink(page: Page, path: string): Locator {
	return page.getByRole("banner").locator(`:scope > nav a[href="${path}"]`);
}

async function requireLayout(page: Page): Promise<void> {
	const issues = await page.evaluate((): string[] => {
		const issues: string[] = [];
		if (document.documentElement.scrollWidth > window.innerWidth)
			issues.push("horizontal overflow");
		for (const element of document.querySelectorAll<HTMLElement>(
			"a, summary",
		)) {
			const box = element.getBoundingClientRect();
			if (
				!element.getClientRects().length ||
				box.right <= 0 ||
				element.closest("p")
			)
				continue;
			if (box.width < 48 || box.height < 48)
				issues.push(`small target: ${element.textContent?.trim()}`);
		}
		return issues;
	});
	expect(issues).toEqual([]);
}

async function requireDecorations(page: Page): Promise<void> {
	await page.mouse.move(0, 0);
	const navigation = page.getByRole("banner").locator(":scope > nav a");
	await expect(navigation).toHaveCount(3);
	for (const link of await navigation.all()) {
		await expect(link).toHaveCSS("text-decoration-line", "none");
		await expect(link.locator(".link-label")).toHaveCSS(
			"text-decoration-line",
			"none",
		);
		await expect(link.locator("svg")).toHaveAttribute("aria-hidden", "true");
		await expect(link.locator("svg")).toHaveCSS("text-decoration-line", "none");
		await expect(link).toHaveAccessibleName(/\S/);
	}
	const hovered = navigation.nth(1);
	await hovered.hover();
	await expect(hovered.locator(".link-label")).toHaveCSS(
		"text-decoration-line",
		"underline",
	);
	await expect(hovered.locator("svg")).toHaveCSS(
		"text-decoration-line",
		"none",
	);
	await expect(hovered).toHaveCSS("text-decoration-line", "none");
	await page.mouse.move(0, 0);
	const summary = page.locator("summary");
	await expect(summary).toHaveCSS("text-decoration-line", "none");
	await expect(summary).toHaveCSS("border-top-style", "solid");
	const hint = summary.locator('span[lang="en"]');
	if (await hint.count()) {
		expect(
			await hint.evaluate(
				(element): boolean =>
					element.getBoundingClientRect().height <=
					Number.parseFloat(getComputedStyle(element).lineHeight) + 1,
			),
		).toBe(true);
	}
	for (const link of await page.getByRole("main").getByRole("link").all()) {
		const label = link.locator(".link-label");
		await expect((await label.count()) ? label : link).toHaveCSS(
			"text-decoration-line",
			"underline",
		);
		if (await label.count()) {
			await expect(link).toHaveCSS("text-decoration-line", "none");
			await expect(link.locator("svg")).toHaveCSS(
				"text-decoration-line",
				"none",
			);
		}
	}
}

async function requireAccessiblePage(page: Page): Promise<void> {
	const result = await new AxeBuilder({ page }).analyze();
	expect(result.violations).toEqual([]);
}

for (const [index, locale] of locales.entries()) {
	test(`${locale.language} navigates when styles and icons fail`, async ({
		page,
	}): Promise<void> => {
		const failed = new Set<string>();
		await page.route(
			/\/(?:styles\.css|icons\.svg)$/,
			async (route: Route): Promise<void> => {
				failed.add(new URL(route.request().url()).pathname);
				await route.abort();
			},
		);
		await page.goto(locale.path);
		for (const content of contents) {
			if (content) await headerLink(page, locale.path + content).click();
			await expect(page).toHaveURL(locale.path + content);
			await expect(
				page.getByRole("main").getByRole("heading", { level: 1 }),
			).toBeVisible();
		}
		await page.locator("summary").click();
		await page.getByRole("link", { name: "English", exact: true }).click();
		await expect(page).toHaveURL("/en/privacy/");
		expect([...failed].sort()).toEqual(["/icons.svg", "/styles.css"]);
	});

	test(`${locale.language} follows the complete page navigation`, async ({
		page,
	}, info): Promise<void> => {
		const errors: string[] = [];
		page.on("pageerror", (error): void => {
			errors.push(error.message);
		});
		await page.goto(locale.path);
		for (const content of contents) {
			if (content) await headerLink(page, locale.path + content).click();
			await expect(page).toHaveURL(locale.path + content);
			await expect(page.locator("html")).toHaveAttribute(
				"lang",
				locale.language,
			);
			await expect(
				page.getByRole("main").getByRole("heading", { level: 1 }),
			).toBeVisible();
			await expect(headerLink(page, locale.path + content)).toHaveAttribute(
				"aria-current",
				"page",
			);
			await requireLayout(page);
			await requireDecorations(page);
			await requireAccessiblePage(page);
			await page.getByRole("banner").screenshot({
				path: info.outputPath(
					`${content.replace("/", "") || "home"}-header.png`,
				),
			});
			await page.locator("summary").click();
			await expect(page.locator("details")).toHaveJSProperty("open", true);
			await expect(page.locator("details nav")).toBeVisible();
			await requireLayout(page);
			await requireAccessiblePage(page);
		}
		await page.goBack();
		await expect(page).toHaveURL(`${locale.path}support/`);
		await headerLink(page, locale.path).click();
		await expect(page).toHaveURL(locale.path);
		expect(errors).toEqual([]);
	});

	test(`${locale.language} uses the keyboard to skip content and change language`, async ({
		page,
	}): Promise<void> => {
		for (const content of contents) {
			await page.goto(locale.path + content);
			const skip = page.locator("a.skip");
			await page.keyboard.press("Tab");
			await expect(skip).toBeFocused();
			await expect(skip).toBeInViewport();
			await expect(skip).toHaveCSS("outline-width", "3px");
			await page.keyboard.press("Enter");
			await expect(page.getByRole("main")).toBeFocused();
			await page.keyboard.press("Tab");
			await expect(
				page.getByRole("main").getByRole("link").first(),
			).toBeFocused();
			await page.goto(locale.path + content);
			await page.keyboard.press("Tab");
			await page.keyboard.press("Tab");
			await expect(headerLink(page, locale.path)).toBeFocused();
			await expect(headerLink(page, locale.path)).toHaveCSS(
				"outline-width",
				"3px",
			);
			await page.keyboard.press("Tab");
			await page.keyboard.press("Tab");
			await page.keyboard.press("Tab");
			await expect(page.locator("summary")).toBeFocused();
			await expect(page.locator("summary")).toHaveCSS("outline-width", "3px");
			await page.keyboard.press("Space");
			await expect(page.locator("details")).toHaveJSProperty("open", true);
			await expect(page.locator("details nav")).toBeVisible();
			const targetIndex = (index + 1) % locales.length;
			const target = locales[targetIndex];
			for (let tab = 0; tab <= targetIndex; tab++)
				await page.keyboard.press("Tab");
			await expect(
				page.getByRole("link", { name: target.name, exact: true }),
			).toBeFocused();
			await page.keyboard.press("Enter");
			await expect(page).toHaveURL(target.path + content);
			await expect(page.locator("html")).toHaveAttribute(
				"lang",
				target.language,
			);
		}
	});

	test(`${locale.language} reflows doubled text and spacing`, async ({
		page,
	}, info): Promise<void> => {
		for (const content of contents) {
			await page.goto(locale.path + content);
			await page.addStyleTag({
				content:
					"html{font-size:200%!important}body *{line-height:1.5!important;letter-spacing:.12em!important;word-spacing:.16em!important}p{margin-block:2em!important}",
			});
			await expect(page.locator("body")).toHaveCSS("font-size", "36px");
			await requireLayout(page);
			await page.locator("summary").click();
			await requireLayout(page);
			if (content === "privacy/")
				await page.screenshot({
					path: info.outputPath("enlarged-privacy.png"),
					fullPage: true,
				});
		}
	});
}

test.describe("without page JavaScript", (): void => {
	test.use({ javaScriptEnabled: false });
	for (const locale of locales) {
		test(`${locale.language} opens the native language disclosure`, async ({
			page,
		}): Promise<void> => {
			await page.goto(`${locale.path}privacy/`);
			await page.locator("summary").click();
			await page.getByRole("link", { name: "English", exact: true }).click();
			await expect(page).toHaveURL("/en/privacy/");
			await headerLink(page, "/en/support/").click();
			await expect(page).toHaveURL("/en/support/");
		});
	}
});

test("rejects overflow and undersized controls", async ({
	page,
}): Promise<void> => {
	await page.goto("/");
	const viewport = page.viewportSize();
	if (!viewport) throw new Error("The test requires a fixed viewport.");
	await page.addStyleTag({
		content: `body{min-width:${viewport.width + 100}px}header nav a{min-height:1px;min-width:1px;padding:0;font-size:8px}`,
	});
	await expect(requireLayout(page)).rejects.toThrow();
});

test("rejects underlining the complete icon target", async ({
	page,
}): Promise<void> => {
	await page.goto("/");
	await page.addStyleTag({ content: "a{text-decoration-line:underline}" });
	await expect(requireDecorations(page)).rejects.toThrow();
});
