defmodule DalaDev.ScreenBaseline do
  @moduledoc """
  Screenshot baselines for cheap visual regression between deploys.

  Save a named baseline once, then after code changes re-capture and compare.
  A match tells you the screen is byte-identical to before; a difference
  saves the new capture next to the baseline for eyeballing.

  Baselines are per-device (a Pixel and an iPhone never agree) and live in
  `.dala/screenshots/<device-id>/` so they can be committed or gitignored
  per project taste.

  Comparison is exact-bytes. Screenshots of a static screen on the same
  device/OS are deterministic in practice; when they aren't (clock in the
  status bar, animations), treat this as a smoke signal, not a pixel-perfect
  assertion tool.
  """

  alias DalaDev.{Device, ScreenCapture}

  @baseline_dir ".dala/screenshots"

  @type compare_result ::
          {:ok, :match}
          | {:ok, {:changed, %{baseline: String.t(), current: String.t(), size_a: pos_integer(), size_b: pos_integer()}}}
          | {:error, term()}

  @doc "Directory holding baselines for `device_id`. Public for testing."
  @spec device_dir(String.t()) :: String.t()
  def device_dir(device_id), do: Path.join(@baseline_dir, sanitize(device_id))

  @doc "Path of the baseline file for `name`. Public for testing."
  @spec baseline_path(String.t(), String.t()) :: String.t()
  def baseline_path(device_id, name),
    do: Path.join(device_dir(device_id), "#{sanitize(name)}.png")

  @doc "Path where a differing capture gets written for comparison."
  @spec diff_path(String.t(), String.t()) :: String.t()
  def diff_path(device_id, name), do: Path.join(device_dir(device_id), "#{sanitize(name)}.new.png")

  @doc """
  Captures `device_ref` and stores it as baseline `name`.
  Returns `{:ok, path}`.

  Test seam: `opts[:capture]` overrides the capture call (defaults to
  `ScreenCapture.capture/2`; receives `(device_ref, capture_opts)`).
  """
  @spec save(ScreenCapture.device_ref(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def save(device_ref, name, opts \\ []) do
    capture = Keyword.get(opts, :capture, &ScreenCapture.capture/2)

    with {:ok, device_id} <- resolve_device_id(device_ref) do
      path = baseline_path(device_id, name)
      File.mkdir_p!(Path.dirname(path))

      case capture.(device_ref, save_as: path) do
        {:ok, ^path} -> {:ok, path}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Captures `device_ref` fresh and compares against baseline `name`.

  Returns:

    * `{:ok, :match}` — bytes identical
    * `{:ok, {:changed, details}}` — differs; fresh capture saved at
      `diff_path/2`, details include both paths and sizes
    * `{:error, :no_baseline}` — nothing saved under that name yet
    * `{:error, reason}` — capture failure

  Test seam: `opts[:capture]` overrides the capture call (defaults to
  `ScreenCapture.capture/2`; receives `(device_ref, [])`, returns
  `{:ok, bytes}` / `{:error, reason}`).
  """
  @spec compare(ScreenCapture.device_ref(), String.t(), keyword()) :: compare_result()
  def compare(device_ref, name, opts \\ []) do
    capture = Keyword.get(opts, :capture, &ScreenCapture.capture/2)

    with {:ok, device_id} <- resolve_device_id(device_ref),
         {:ok, baseline} <- existing_baseline(device_id, name),
         {:ok, fresh} <- capture.(device_ref, []) do
      case File.read(baseline) do
        {:ok, old_bytes} ->
          apply_diff(name, device_id, old_bytes, fresh)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Pure comparison of two captures. Public test seam for the diff logic.
  """
  @spec compare_bytes(binary(), binary()) :: :match | {:changed, pos_integer(), pos_integer()}
  def compare_bytes(old_bytes, fresh) when old_bytes == fresh, do: :match

  def compare_bytes(old_bytes, fresh),
    do: {:changed, byte_size(old_bytes), byte_size(fresh)}

  defp apply_diff(name, device_id, old_bytes, fresh) do
    case compare_bytes(old_bytes, fresh) do
      :match ->
        {:ok, :match}

      {:changed, size_a, size_b} ->
        diff_file = diff_path(device_id, name)
        File.write!(diff_file, fresh)

        {:ok,
         {:changed,
          %{
            baseline: baseline_path(device_id, name),
            current: diff_file,
            size_a: size_a,
            size_b: size_b
          }}}
    end
  end

  # ── Internals ───────────────────────────────────────────────────────────────

  defp existing_baseline(device_id, name) do
    path = baseline_path(device_id, name)

    if File.exists?(path),
      do: {:ok, path},
      else: {:error, :no_baseline}
  end

  defp resolve_device_id(%Device{} = d), do: {:ok, Device.display_id(d)}

  defp resolve_device_id(ref) do
    devices = DalaDev.Discovery.Android.list_devices() ++ DalaDev.Discovery.IOS.list_devices()

    found =
      Enum.find(devices, fn d ->
        Device.match_id?(d, to_string(ref)) or d.node == ref
      end)

    case found do
      nil -> {:error, :device_not_found}
      d -> {:ok, Device.display_id(d)}
    end
  end

  # Replace unsafe chars, then collapse consecutive dots so a name like
  # "../evil" can't smuggle a parent-directory component.
  defp sanitize(id) do
    id
    |> to_string()
    |> String.replace(DalaDev.Utils.compile_regex("[^A-Za-z0-9._-]"), "_")
    |> String.replace(DalaDev.Utils.compile_regex("\\.{2,}"), "_")
  end
end
