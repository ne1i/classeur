package classeurtool

// The shop: classeur's licence, sold through Paddle by the toolkit's licence Worker. Its six pages (pricing, thanks, terms,
// refunds, privacy, imprint) are the toolkit's templates, filled at each `site build` (Meta.shop, site.odin). Until it has
// Paddle's client token, the price id and the licence Worker's address, the buy button says "Coming soon" (docs/licence.md
// of gui_toolkit, "What the maintainer does at the end").

import tk_site "gt:site"
import classeur_licence "../../src/licence"

shop :: proc() -> tk_site.Shop {
	return {
		name           = "classeur",
		icon           = "../img/logo.png",
		product_title  = "Classeur User License",
		price          = "29&nbsp;&euro;",
		price_note     = "",
		environment    = "production",
		client_token   = "live_44c43ca90843b67eeccfd8275fc",   // Paddle's client-side token (public: it is in the page)
		edition        = "supporter",
		price_id       = "pri_01m7fyaky9wrzkd5zk9h6xsz3e",   // what `classeurtool paddle -apply` printed
		worker         = "https://classeur-licence.sacha-42a.workers.dev",
		thanks         = "https://classeur.froment.software/thanks/",
		help           = REPOSITORY + "/issues/new",
		register       = "Open the file with Classeur, or paste the key in <strong>Settings &gt; General &gt; Licence</strong>.",
		extension      = classeur_licence.PRODUCT.file_extension,
		repository     = REPOSITORY,
		seller         = tk_site.SELLER_FROMENT,
		code_licence   = "MIT License",
		platform       = "Linux, x64, and Windows 10 or 11, x64.",
		network        = tk_site.NETWORK_UPDATES_ONLY,
		stylesheet     = "../style.css",
		home           = "../",
		updated        = "2026-11-13",
	}
}
