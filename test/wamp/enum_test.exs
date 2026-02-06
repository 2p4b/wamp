defmodule Wamp.EnumTest do
    use ExUnit.Case, async: true

    describe "remove_item_at/2" do
        test "removes element at the given index" do
            assert Wamp.Enum.remove_item_at([1, 2, 3], 1) == [1, 3]
        end

        test "removes first element" do
            assert Wamp.Enum.remove_item_at([1, 2, 3], 0) == [2, 3]
        end

        test "removes last element" do
            assert Wamp.Enum.remove_item_at([1, 2, 3], 2) == [1, 2]
        end

        test "returns empty list when removing only element" do
            assert Wamp.Enum.remove_item_at([:a], 0) == []
        end

        test "handles index beyond list length" do
            assert Wamp.Enum.remove_item_at([1, 2], 5) == [1, 2]
        end
    end

    describe "replace_item_at/3" do
        test "replaces element at the given index" do
            assert Wamp.Enum.replace_item_at([1, 2, 3], 1, :x) == [1, :x, 3]
        end

        test "replaces first element" do
            assert Wamp.Enum.replace_item_at([1, 2, 3], 0, :a) == [:a, 2, 3]
        end

        test "replaces last element" do
            assert Wamp.Enum.replace_item_at([1, 2, 3], 2, :z) == [1, 2, :z]
        end

        test "appends when index equals list length" do
            assert Wamp.Enum.replace_item_at([1, 2], 2, 3) == [1, 2, 3]
        end
    end
end
