// Pro's price in the US, at its launch price: the one place it is written. The pages, the structured data and llms.txt
// all read it (through lib/site.ts), so a price change is this one edit (docs/app-store/app-store-connect-steps.md).
// It has its own file, with no imports, because lib/docs.ts needs it and lib/site.ts imports lib/docs.ts.
// PRO_PRICE is the schema.org number; PRO_PRICE_TEXT is for copy.
export const PRO_PRICE = "4.99";
export const PRO_PRICE_TEXT = `$${PRO_PRICE}`;
