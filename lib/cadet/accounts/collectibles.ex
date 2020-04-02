defmodule Cadet.Collectibles do
  import Ecto.Query
  alias Cadet.Accounts.User
  alias Ecto.Multi
  import Cadet.Repo
  import Ecto.Repo
  
  # simply return the collectibles of the user, within a single map
  def user_collectibles(user) do
    user.collectibles
  end

  def update_collectibles(pic_nickname, pic_name, user) do
    changeset =
    Ecto.Changeset.cast(user, %{collectibles: Map.put(user_collectibles(user), pic_nickname, pic_name)},[:collectibles])
    # really simple error handling action
    with {:ok, _} <- Cadet.Repo.update!(changeset) do
        {:ok, nil}
    else
      {:error, _} ->
        {:error, {:internal_server_error, "Please try again later."}}
    end
  end

  # should be idle since we are not going to delete students' collectibles
  # but provide the function delete_collectibles here for future extension
  def delete_all_collectibles(user) do
    changeset =
    Ecto.Changeset.cast(user, %{collectibles: %{}},[:collectibles])
    Cadet.Repo.update!(changeset)
  end
end
