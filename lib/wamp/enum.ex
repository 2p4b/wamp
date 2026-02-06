defmodule Wamp.Enum do
    @moduledoc """
    List utility functions used internally for index-based list operations.
    """

    @doc """
    Removes the element at the given index from the list.

    ## Examples

        iex> Wamp.Enum.remove_item_at([1, 2, 3], 1)
        [1, 3]

    """
    def remove_item_at(items, index) when is_list(items) do
        head = Enum.slice(items, 0, index)
        tail = Enum.slice(items, index + 1, length(items))
        head ++ tail
    end

    @doc """
    Replaces the element at the given index with the provided value.

    ## Examples

        iex> Wamp.Enum.replace_item_at([1, 2, 3], 1, :x)
        [1, :x, 3]

    """
    def replace_item_at(items, index, value)
    when is_list(items) and is_integer(index) do
        head = Enum.slice(items, 0, index)
        tail = Enum.slice(items, index + 1, length(items))
        head ++ [value] ++ tail
    end


end
