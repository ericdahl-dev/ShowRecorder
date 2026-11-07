import { APP_ROWS, CHECKED, type AppRow } from "@/lib/bestApp";

// The best-app comparison table (#1085) and its source list, both from APP_ROWS in lib/bestApp.ts.

const COLUMNS: readonly [keyof AppRow, string][] = [
  ["price", "Price model"],
  ["perChannel", "A file per channel"],
  ["inputs", "Channels at once"],
  ["platforms", "Runs on"],
  ["names", "Channel names from the mixer"],
  ["editing", "Editing on the device"],
];

export function BestAppTable() {
  return (
    <div className="compare-scroll" role="region" aria-label="Apps compared" tabIndex={0}>
      {/* The roles keep it a table for screen readers when phones stack the rows (display: block; globals.css). */}
      <table className="compare-table guides-table" role="table">
        <caption className="sr-only">
          What each iPhone and iPad app does for multitrack recording from a USB mixer, as of {CHECKED}
        </caption>
        <thead role="rowgroup">
          <tr role="row">
            <th scope="col" role="columnheader">
              App
            </th>
            {COLUMNS.map(([, label]) => (
              <th key={label} scope="col" role="columnheader">
                {label}
              </th>
            ))}
          </tr>
        </thead>
        <tbody role="rowgroup">
          {APP_ROWS.map((row) => (
            <tr key={row.id} role="row">
              <th scope="row" role="rowheader">
                {row.name}
                <span className="row-note">
                  {row.maker}.{" "}
                  <a href={row.source}>
                    Source
                  </a>
                  , checked {CHECKED}
                </span>
              </th>
              {COLUMNS.map(([key, label]) => (
                <td key={key} role="cell" data-product={label}>
                  {row[key]}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// Every page the table's facts come from, with the day each was read.
export function BestAppSources() {
  return (
    <ul>
      {APP_ROWS.map((row) => (
        <li key={row.id}>
          {row.name}: <a href={row.source}>{row.source}</a>
          {row.extraSource ? (
            <>
              {" "}
              and <a href={row.extraSource}>{row.extraSource}</a>
            </>
          ) : null}
          , checked {CHECKED}.
        </li>
      ))}
    </ul>
  );
}
