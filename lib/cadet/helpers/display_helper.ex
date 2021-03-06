defmodule Cadet.DisplayHelper do
  @moduledoc """
  Contains utility functions that may be used for modules that need to be displayed to the user.
  """
  import Ecto.Changeset

  def put_display_order(changeset, collection) do
    if Enum.empty?(collection) do
      change(changeset, %{display_order: 1})
    else
      last = Enum.max_by(collection, & &1.display_order)
      change(changeset, %{display_order: last.display_order + 1})
    end
  end

  @spec full_error_messages(keyword({String.t(), term()})) :: String.t()
  def full_error_messages(errors) do
    errors
    |> Enum.map(fn {key, {message, _}} -> "#{key} #{message}" end)
    |> Enum.join(", ")
  end

  def create_invalid_changeset_with_error(key, message) do
    add_error(%Ecto.Changeset{}, key, message)
  end
end
