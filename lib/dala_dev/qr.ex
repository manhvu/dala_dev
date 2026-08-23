defmodule DalaDev.QR do
  @moduledoc """
  Renders QR codes in the terminal using Unicode half-block characters.
  Uses eqrcode for matrix generation.
  """

  @doc "Prints a QR code for the given content to stdout."
  @spec print(String.t()) :: :ok
  def print(content) do
    _ = DalaDev.Output.info(render(content))
    :ok
  end

  @doc "Returns the QR code as a string of Unicode blocks."
  @spec render(String.t()) :: String.t()
  def render(content) do
    matrix =
      content
      |> EQRCode.encode()
      |> Map.get(:matrix)
      |> Tuple.to_list()
      |> Enum.map(&Tuple.to_list/1)

    # Add a quiet zone (4 cells of whitespace border required by spec)
    rows = with_quiet_zone(matrix)

    # Process pairs of rows using half-block characters:
    # ▀ = top filled, bottom empty
    # ▄ = top empty, bottom filled
    # █ = both filled
    # ' ' = both empty
    rows
    |> Enum.chunk_every(2, 2, [List.duplicate(0, length(List.first(rows)))])
    |> Enum.map_join("\n", fn [top_row, bot_row] ->
      Enum.zip(top_row, bot_row)
      |> Enum.map_join("", fn
        {1, 1} -> "█"
        {1, 0} -> "▀"
        {0, 1} -> "▄"
        {0, 0} -> " "
      end)
    end)
  end

  defp with_quiet_zone(matrix) do
    width = length(List.first(matrix))
    empty_row = List.duplicate(0, width + 8)
    side_pad = List.duplicate(0, 4)

    padded_rows = Enum.map(matrix, fn row -> side_pad ++ row ++ side_pad end)
    List.duplicate(empty_row, 4) ++ padded_rows ++ List.duplicate(empty_row, 4)
  end
end
