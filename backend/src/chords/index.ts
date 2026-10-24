import { createAnthropicProvider } from "./anthropic";
import { createOpenAIProvider } from "./openai";
import { PROVIDER_NAMES, type ChordProvider, type ProviderName } from "./provider";

export { ChordAnnotationError, PROVIDER_NAMES, type ChordPrompt, type ChordProvider, type ProviderName } from "./provider";

/** The AI settings the Worker reads from its environment. Only the keys you set are used. */
export interface AIEnv {
  ANTHROPIC_API_KEY?: string;
  ANTHROPIC_MODEL?: string;
  OPENAI_API_KEY?: string;
  OPENAI_MODEL?: string;
  /** Provider to use when a request doesn't ask for one. Defaults to the first configured one. */
  AI_PROVIDER?: string;
}

function create(name: ProviderName, env: AIEnv): ChordProvider | null {
  switch (name) {
    case "anthropic":
      return env.ANTHROPIC_API_KEY ? createAnthropicProvider(env.ANTHROPIC_API_KEY, env.ANTHROPIC_MODEL || undefined) : null;
    case "openai":
      return env.OPENAI_API_KEY ? createOpenAIProvider(env.OPENAI_API_KEY, env.OPENAI_MODEL || undefined) : null;
  }
}

export function configuredProviders(env: AIEnv): ProviderName[] {
  const keys: Record<ProviderName, string | undefined> = { anthropic: env.ANTHROPIC_API_KEY, openai: env.OPENAI_API_KEY };
  return PROVIDER_NAMES.filter((name) => Boolean(keys[name]));
}

export class ProviderSelectionError extends Error {}

/** Picks the provider: the one requested, else `AI_PROVIDER`, else the first with a key. */
export function selectProvider(env: AIEnv, requested?: ProviderName): ChordProvider {
  const configured = configuredProviders(env);
  if (configured.length === 0) {
    throw new ProviderSelectionError("No AI provider is configured: set ANTHROPIC_API_KEY or OPENAI_API_KEY");
  }
  const fallback = env.AI_PROVIDER as ProviderName | undefined;
  const name = requested ?? (fallback && configured.includes(fallback) ? fallback : configured[0]!);
  const provider = create(name, env);
  if (!provider) {
    throw new ProviderSelectionError(`Provider "${name}" is not configured; available: ${configured.join(", ")}`);
  }
  return provider;
}
