defmodule DalaDev.ErrorViewTest do
  use ExUnit.Case, async: true

  alias DalaDev.ErrorView

  defp html(rendered) do
    rendered
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  test "renders 404 page" do
    page = ErrorView.render("404.html", %{}) |> html()
    assert page =~ "404"
    assert page =~ "Not found"
  end

  test "renders 500 page" do
    page = ErrorView.render("500.html", %{}) |> html()
    assert page =~ "500"
    assert page =~ "Internal server error"
  end

  test "renders template not found gracefully" do
    # Unknown templates fall back to Phoenix's status-message lookup
    assert ErrorView.render("bogus.html", %{}) == "Internal Server Error"
  end
end
