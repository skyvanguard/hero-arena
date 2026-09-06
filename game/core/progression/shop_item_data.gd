class_name ShopItemData
extends Resource
## D31 (monetization-ready shop): one shop listing.
##
## The cosmetics-only rule is enforced BY THE SCHEMA: an item's entire
## effect is a (hero, variant) cosmetic unlock - there is no field for a
## stat bonus, a weapon, or anything gameplay-affecting, so a gameplay
## item cannot even be represented in content. `validate` additionally
## checks that the effect resolves (real hero, real palette slot) and
## that the free default variant (index 0) is never sold.
##
## Monetization-ready: the purchase engine is currency-agnostic (it
## debits whatever `currency` the item is priced in). Today the only
## currency is "gear" (earned in matches - no real money involved);
## a payment provider can later introduce new currencies (e.g. IAP gems)
## without touching the purchase/ownership path.

@export var id := ""
@export var display_name := ""
@export var desc := ""
## The cosmetic effect: this variant of this hero.
@export var hero_id := ""
@export var variant_idx := 1
## Price in the given currency (must be > 0).
@export var price := 300
@export var currency := "gear"
