defmodule Utils.Queue do
  # This is not a real queue omegalul
  defstruct [:data, :length, :current]

  def new, do: %Utils.Queue{data: [], length: 0, current: 0}

  def head(%Utils.Queue{} = q) do
    current = sanitize_index(q.current, q.length)
    Enum.at(q.data, current)
  end

  def dequeue(%Utils.Queue{} = q) do
    el = head(q)
    current = sanitize_index(q.current + 1, q.length)
    {el, Map.put(q, :current, current)}
  end

  def enqueue(%Utils.Queue{} = q, element) do
    data = List.insert_at(q.data, -1, element)
    length = q.length + 1

    q
    |> Map.put(:length, length)
    |> Map.put(:data, data)
  end

  def to_list(%Utils.Queue{data: data}), do: data

  def empty?(%Utils.Queue{length: len}), do: len == 0

  defp sanitize_index(index, length) do
    if index >= length do
      index - length
    else
      index
    end
  end
end
