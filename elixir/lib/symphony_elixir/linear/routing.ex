defmodule SymphonyElixir.Linear.Routing do
  @moduledoc """
  Derives per-issue repository routing from Linear labels.

  Supported labels:

    * `repo:owner/name`
    * `branch:name` (optional override)
  """

  alias SymphonyElixir.Linear.Issue

  @type selection :: %{
          repo: String.t() | nil,
          branch: String.t() | nil
        }

  @spec selection(Issue.t() | map() | nil) :: selection()
  def selection(issue) do
    labels = label_names(issue)

    %{
      repo: extract_prefixed_label_value(labels, "repo:"),
      branch: extract_prefixed_label_value(labels, "branch:")
    }
  end

  @spec repo(Issue.t() | map() | nil) :: String.t() | nil
  def repo(issue) do
    issue
    |> selection()
    |> Map.get(:repo)
  end

  @spec branch(Issue.t() | map() | nil) :: String.t() | nil
  def branch(issue) do
    issue
    |> selection()
    |> Map.get(:branch)
  end

  @spec hook_env(Issue.t() | map() | String.t() | nil) :: [{String.t(), String.t()}]
  def hook_env(issue) do
    issue_context = issue_context(issue)
    route = selection(issue)

    [
      {"SYMPHONY_ISSUE_ID", issue_context.issue_id},
      {"SYMPHONY_ISSUE_IDENTIFIER", issue_context.issue_identifier},
      {"SYMPHONY_REPO", route.repo},
      {"SYMPHONY_BRANCH", route.branch}
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp label_names(%Issue{} = issue), do: Issue.label_names(issue)
  defp label_names(%{labels: labels}) when is_list(labels), do: labels
  defp label_names(_issue), do: []

  defp extract_prefixed_label_value(labels, prefix) do
    normalized_prefix = String.downcase(prefix)

    Enum.find_value(labels, fn
      label when is_binary(label) ->
        label
        |> String.trim()
        |> String.downcase()
        |> prefixed_label_value(normalized_prefix)

      _ ->
        nil
    end)
  end

  defp prefixed_label_value(label, normalized_prefix) do
    if String.starts_with?(label, normalized_prefix) do
      label
      |> String.replace_prefix(normalized_prefix, "")
      |> String.trim()
      |> empty_to_nil()
    end
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value

  defp issue_context(%{issue_id: issue_id, issue_identifier: issue_identifier}) do
    %{
      issue_id: issue_id,
      issue_identifier: issue_identifier || "issue"
    }
  end

  defp issue_context(%{id: issue_id, identifier: identifier}) do
    %{
      issue_id: issue_id,
      issue_identifier: identifier || "issue"
    }
  end

  defp issue_context(identifier) when is_binary(identifier) do
    %{
      issue_id: nil,
      issue_identifier: identifier
    }
  end

  defp issue_context(_identifier) do
    %{
      issue_id: nil,
      issue_identifier: "issue"
    }
  end
end
