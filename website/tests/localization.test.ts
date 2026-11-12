import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";
import { type DefaultTreeAdapterMap, parse } from "parse5";

type Element = DefaultTreeAdapterMap["element"];
type Node = DefaultTreeAdapterMap["node"];

type Language = "ja" | "en" | "zh-Hans" | "zh-Hant";
type Content = "" | "support/" | "privacy/";

interface Locale {
	language: Language;
	path: string;
}

interface Page extends Locale {
	content: Content;
}

const locales: readonly Locale[] = [
	{ language: "ja", path: "/" },
	{ language: "en", path: "/en/" },
	{ language: "zh-Hans", path: "/zh-Hans/" },
	{ language: "zh-Hant", path: "/zh-Hant/" },
];
const contents: readonly Content[] = ["", "support/", "privacy/"];
const pages: readonly Page[] = locales.flatMap((locale) =>
	contents.map((content) => ({
		...locale,
		path: locale.path + content,
		content,
	})),
);

function elements(node: Node): Element[] {
	const result: Element[] = "tagName" in node ? [node] : [];
	if ("childNodes" in node) {
		for (const child of node.childNodes) result.push(...elements(child));
	}
	return result;
}

function attribute(element: Element, name: string): string | undefined {
	return element.attrs.find((item) => item.name === name)?.value;
}

function localizedDocument(source: string, page: Page): Element[] {
	const nodes = elements(parse(source));
	const root = nodes.find((node) => node.tagName === "html");
	assert.ok(root);
	assert.equal(attribute(root, "lang"), page.language);
	const disclosure = nodes.find((node) => node.tagName === "details");
	assert.ok(disclosure);
	assert.equal(attribute(disclosure, "role"), undefined);
	assert.equal(attribute(disclosure, "open"), undefined);
	const children = elements(disclosure).slice(1);
	assert.equal(children[0]?.tagName, "summary");
	const summary = children[0];
	assert.ok(summary);
	const languageLinks = children.filter((node) => node.tagName === "a");
	assert.equal(languageLinks.length, locales.length);
	for (const locale of locales) {
		const links = languageLinks.filter(
			(node) => attribute(node, "hreflang") === locale.language,
		);
		assert.equal(links.length, 1);
		const link = links[0];
		assert.ok(link);
		assert.equal(attribute(link, "lang"), locale.language);
		assert.equal(attribute(link, "href"), locale.path + page.content);
		assert.equal(
			attribute(link, "aria-current"),
			locale.language === page.language ? "page" : undefined,
		);
	}
	for (const node of nodes) {
		const language = attribute(node, "lang");
		if (!language || node.tagName === "a") continue;
		if (elements(summary).includes(node) && language === "en") continue;
		assert.equal(language, page.language);
	}
	const firstLink = nodes.find((node) => node.tagName === "a");
	assert.ok(firstLink);
	assert.equal(attribute(firstLink, "class"), "skip");
	assert.equal(attribute(firstLink, "href"), "#main");
	const main = nodes.find((node) => node.tagName === "main");
	assert.ok(main);
	assert.equal(attribute(main, "id"), "main");
	assert.equal(attribute(main, "tabindex"), "-1");
	for (const link of nodes.filter((node) => node.tagName === "a")) {
		const standalone =
			link.parentNode?.nodeName === "nav" ||
			["skip", "action"].includes(attribute(link, "class") ?? "");
		if (!standalone) continue;
		const icon = link.childNodes.find(
			(node) => "tagName" in node && node.tagName === "svg",
		);
		assert.ok(icon && "tagName" in icon);
		assert.equal(attribute(icon, "aria-hidden"), "true");
		const label = link.childNodes.find(
			(node) => "tagName" in node && attribute(node, "class") === "link-label",
		);
		assert.ok(label && "tagName" in label);
		assert.ok(label.childNodes.every((node) => node.nodeName === "#text"));
	}
	return nodes;
}

const fixture = `<!DOCTYPE html><html lang="ja"><head><title>Support</title></head><body>
<a class="skip" href="#main"><svg aria-hidden="true"><use href="/icons.svg#arrow-down"></use></svg><span class="link-label">本文へ移動</span></a>
<details><summary>言語を変更 / <span lang="en">Change language</span></summary><nav>
<a lang="ja" hreflang="ja" href="/support/" aria-current="page"><svg aria-hidden="true"><use href="/icons.svg#languages"></use></svg><span class="link-label">日本語</span></a>
<a lang="en" hreflang="en" href="/en/support/"><svg aria-hidden="true"><use href="/icons.svg#languages"></use></svg><span class="link-label">English</span></a>
<a lang="zh-Hans" hreflang="zh-Hans" href="/zh-Hans/support/"><svg aria-hidden="true"><use href="/icons.svg#languages"></use></svg><span class="link-label">简体中文</span></a>
<a lang="zh-Hant" hreflang="zh-Hant" href="/zh-Hant/support/"><svg aria-hidden="true"><use href="/icons.svg#languages"></use></svg><span class="link-label">繁體中文</span></a>
</nav></details><main id="main" tabindex="-1"><p>問い合わせ</p></main></body></html>`;
const support: Page = {
	path: "/support/",
	language: "ja",
	content: "support/",
};

test("accepts four explicit language links preserving the current page", (): void => {
	localizedDocument(fixture, support);
});

for (const [name, source] of [
	[
		"wrong document language",
		fixture.replace('html lang="ja"', 'html lang="en"'),
	],
	[
		"mixed reading languages",
		fixture.replace(
			"</main>",
			'<section lang="en"><p>Contact</p></section></main>',
		),
	],
	[
		"a language switch to a different page",
		fixture.replace('href="/en/support/"', 'href="/en/"'),
	],
	[
		"a missing language",
		fixture.replace('hreflang="zh-Hant"', 'hreflang="en"'),
	],
	["a misleading current language", fixture.replace('aria-current="page"', "")],
	["a simulated menu", fixture.replace("<details>", '<details role="menu">')],
	["an unfocusable main target", fixture.replace('tabindex="-1"', "")],
	[
		"an announced decorative icon",
		fixture.replace('aria-hidden="true"', 'aria-hidden="false"'),
	],
	[
		"an icon inside the decorated label",
		fixture.replace(
			'<span class="link-label">日本語</span>',
			'<span class="link-label"><svg aria-hidden="true"></svg>日本語</span>',
		),
	],
]) {
	test(`refuses ${name}`, (): void => {
		assert.throws(() => localizedDocument(source, support));
	});
}

for (const page of pages) {
	test(`serves ${page.path} in ${page.language} with working local links`, async (): Promise<void> => {
		const file = new URL(`../public${page.path}index.html`, import.meta.url);
		const source = await readFile(file, "utf8");
		const nodes = localizedDocument(source, page);
		const sprite = elements(
			parse(
				await readFile(new URL("../public/icons.svg", import.meta.url), "utf8"),
			),
		);
		for (const use of nodes.filter((node) => node.tagName === "use")) {
			const reference = new URL(
				attribute(use, "href") ?? "",
				"https://gymemo.invalid",
			);
			assert.equal(reference.pathname, "/icons.svg");
			assert.ok(
				sprite.some(
					(node) =>
						node.tagName === "symbol" &&
						attribute(node, "id") === reference.hash.slice(1),
				),
			);
		}
		for (const link of nodes.filter((node) => node.tagName === "a")) {
			const href = attribute(link, "href");
			assert.ok(href);
			const url = new URL(href, `https://gymemo.invalid${page.path}`);
			if (url.protocol === "mailto:") {
				assert.equal(url.pathname, "hi@yasunobu.dev");
				assert.equal(url.searchParams.get("subject"), "gymemo");
				continue;
			}
			assert.equal(url.origin, "https://gymemo.invalid");
			if (!attribute(link, "hreflang")) {
				assert.ok(
					pages.some(
						(target) =>
							target.path === url.pathname && target.language === page.language,
					),
				);
			}
			const target = new URL(
				`../public${url.pathname}index.html`,
				import.meta.url,
			);
			await access(target);
			if (url.hash) {
				const destination = elements(parse(await readFile(target, "utf8")));
				assert.ok(
					destination.some(
						(node) => attribute(node, "id") === url.hash.slice(1),
					),
				);
			}
		}
	});
}
