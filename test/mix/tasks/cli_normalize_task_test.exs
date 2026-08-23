defmodule Mix.Tasks.CLINormalizeTaskTest do
  use ExUnit.Case, async: false

  # Gotcha #37 regression tests: every Mix task must call
  # `DalaDev.Utils.normalize_cli_args/1` as the first statement of run/1 so
  # underscored long flags (`--dry_run`) are rewritten to hyphenated form
  # (`--dry-run`) before OptionParser sees them. Without normalization,
  # OptionParser silently drops underscored flags.
  #
  # These tasks use OptionParser.parse!/2 with strict switch lists, so an
  # unknown flag raises OptionParser.ParseError naming the exact token that
  # reached the parser. Passing an underscored flag through run/1 and
  # asserting the error names the HYPHENATED form proves normalization ran
  # inside run/1 — before the fix the error named the raw underscored token.
  # Both paths raise before any device/network work, so they are safe to run
  # in tests without devices.

  describe "dala.bench run/1 normalizes underscore flags" do
    test "underscored flag reaches OptionParser as hyphenated" do
      assert_raise OptionParser.ParseError, ~r/--beam-flags/, fn ->
        Mix.Tasks.Dala.Bench.run(["--beam_flags", "-S 1:1"])
      end
    end

    test "already-hyphenated flags pass through unchanged" do
      assert_raise OptionParser.ParseError, ~r/--beam-flags/, fn ->
        Mix.Tasks.Dala.Bench.run(["--beam-flags", "-S 1:1"])
      end
    end
  end

  describe "dala.logs run/1 normalizes underscore flags" do
    test "underscored flag reaches OptionParser as hyphenated" do
      assert_raise OptionParser.ParseError, ~r/--no-such-flag/, fn ->
        Mix.Tasks.Dala.Logs.run(["--no_such_flag"])
      end
    end
  end
end
