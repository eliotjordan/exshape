defmodule Exshape do
  @moduledoc """
    This module just contains a helper function for working wtih zip
    archives. If you have a stream of bytes that you want to parse
    directly, use the Shp or Dbf modules to parse.
  """
  alias Exshape.{Dbf, Shp}

  defp open_shp(c, size), do: File.stream!(c, [], size) |> Shp.read
  defp open_dbf(c, size), do: File.stream!(c, [], size) |> Dbf.read


  defp zip(nil, nil, _), do: []
  defp zip(nil, d, size), do: open_dbf(d, size)
  defp zip(s, nil, size), do: open_shp(s, size)
  defp zip(s, d, size), do: Stream.zip(open_shp(s, size), open_dbf(d, size))

  defp projection(nil), do: nil
  defp projection(prj), do: File.read!(prj)

  defp ls_r(cwd) do
    File.ls!(cwd)
    |> Enum.map(&Path.join([cwd, &1]))
    |> Enum.flat_map(fn file ->
      if File.regular?(file) do
        # File
        [file]
      else
        # Dir
        ls_r(file)
      end
    end)
  end

  defp unzip(path, cwd, false), do: :zip.extract(to_charlist(path), cwd: cwd)
  defp unzip(path, cwd, true) do
    {_, 0} = System.cmd("unzip", [path, "-d", to_string(cwd)])
    {:ok, ls_r(cwd)}
  end

  @doc """
    Given a zip file path, unzip it and open streams for the underlying
    shape data.

    Returns a list of all the layers, where each layer is a tuple of layer name,
    projection, and the stream of features

    By default this unzips to `/tmp/exshape_some_uuid`. Make sure
    to clean up when you're done consuming the stream. Pass the `:working_dir`
    option to change this destination.

    By default this reads in 1024 * 512 byte chunks. Pass the `:read_size`
    option to change this.

    By default this shells out to the `unzip` system cmd, to use the built in erlang
    one, pass `unzip_shell: true`. The default behavior is to use the system one because
    the erlang one tends to not support as many formats.

    ```
    [{layer_name, projection, feature_stream}] = Exshape.from_zip("single_layer.zip")
    ```
  """
  @type projection :: String.t
  @type layer_name :: String.t
  @type layer :: {layer_name, projection, Stream.t}
  @spec from_zip(String.t) :: [layer]
  def from_zip(path, opts \\ []) do

    cwd = Keyword.get(opts, :working_dir, '/tmp/exshape_#{UUID.uuid4}')
    size = Keyword.get(opts, :read_size, 1024 * 1024)
    File.mkdir_p!(cwd)
    with {:ok, files} <- unzip(path, cwd, Keyword.get(opts, :unzip_shell, true)) do
      files
      |> Enum.group_by(&Path.rootname/1)
      |> Enum.flat_map(fn {root, components} ->
        prj = projection(Enum.find(components, fn c -> extension_equals(c, ".prj") end))
        shp = Enum.find(components, fn c -> extension_equals(c, ".shp") end)
        dbf = Enum.find(components, fn c -> extension_equals(c, ".dbf") end)

        if !is_nil(shp) && !is_nil(dbf) do
          stream = zip(shp, dbf, size)
          [{Path.basename(root), prj, stream}]
        else
          []
        end
      end)
    end
  end

  defp extension_equals(path, wanted_ext) do
    case Path.extname(path) do
      nil -> false
      ext -> String.downcase(ext) == wanted_ext
    end
  end

end
