defmodule AllojohnTest do
  use ExUnit.Case
  doctest Allojohn

  test "greets the world" do
    assert Allojohn.hello() == :world
  end
end
