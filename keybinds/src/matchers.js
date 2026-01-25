/**
 * Matchers for searchCommands
 *
 * Tree-shakeable: import only what you need.
 *
 * @example
 * import { searchCommands } from 'keybinds'
 * import { fuzzyMatcher } from 'keybinds/matchers'
 *
 * searchCommands(commands, query, context, { matcher: fuzzyMatcher })
 */

/**
 * @typedef {{ score: number, positions?: number[] }} MatchResult
 * @typedef {(query: string, text: string) => MatchResult | null} Matcher
 */

/**
 * Simple substring matcher (case-insensitive)
 *
 * Scores by position: startsWith > includes
 *
 * @type {Matcher}
 */
export function simpleMatcher(query, text) {
  const q = query.toLowerCase()
  const t = text.toLowerCase()

  if (t.startsWith(q)) return { score: 2 }
  if (t.includes(q)) return { score: 1 }
  return null
}

/**
 * Fuzzy sequential character matcher
 *
 * Matches if all query chars appear in order in text.
 * Scores based on consecutive matches and word-start bonuses.
 * Returns positions for highlighting.
 *
 * @type {Matcher}
 */
export function fuzzyMatcher(query, text) {
  const q = query.toLowerCase()
  const t = text.toLowerCase()

  let qi = 0
  let ti = 0
  let score = 0
  let lastMatch = -1
  /** @type {number[]} */
  const positions = []

  while (qi < q.length && ti < t.length) {
    if (q[qi] === t[ti]) {
      positions.push(ti)
      // Consecutive match bonus
      if (ti === lastMatch + 1) score += 2
      // Word start bonus (after space/hyphen/underscore or at beginning)
      if (ti === 0 || ' -_'.includes(t[ti - 1])) score += 3
      // Exact case match bonus
      if (query[qi] === text[ti]) score += 1
      lastMatch = ti
      qi++
    }
    ti++
  }

  // All query chars must be found
  if (qi < q.length) return null

  // Base score from match ratio
  score += Math.round((positions.length / t.length) * 10)

  return { score, positions }
}
