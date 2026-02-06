defmodule Wamp.Enum do

    def remove_item_at(items, index) when is_list(items) do
        head = Enum.slice(items, 0, index)
        tail = Enum.slice(items, index + 1, length(items))
        head ++ tail
    end

    def replace_item_at(items, index, value) 
    when is_list(items) and is_integer(index) do
        head = Enum.slice(items, 0, index)
        tail = Enum.slice(items, index + 1, length(items))
        head ++ [value] ++ tail
    end


end
