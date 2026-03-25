using System.Windows.Media.Imaging;

namespace iPhotoImporter.Services;

/// <summary>
/// Cache LRU en RAM per imatges a resolució completa.
/// Manté les últimes N imatges carregades per navegació ràpida.
/// </summary>
public class ImageCacheService
{
    private readonly int _maxSize;
    private readonly LinkedList<(string Key, BitmapSource Image)> _list = new();
    private readonly Dictionary<string, LinkedListNode<(string Key, BitmapSource Image)>> _map = new();
    private readonly object _lock = new();

    public ImageCacheService(int maxSize = 20)
    {
        _maxSize = maxSize;
    }

    /// <summary>
    /// Obté una imatge de la cache si existeix.
    /// </summary>
    public BitmapSource? Get(string key)
    {
        lock (_lock)
        {
            if (!_map.TryGetValue(key, out var node)) return null;

            // Moure al principi (més recent)
            _list.Remove(node);
            _list.AddFirst(node);
            return node.Value.Image;
        }
    }

    /// <summary>
    /// Afegeix una imatge a la cache. Descarta la més antiga si s'excedeix la capacitat.
    /// </summary>
    public void Put(string key, BitmapSource image)
    {
        lock (_lock)
        {
            if (_map.TryGetValue(key, out var existingNode))
            {
                // Actualitzar i moure al principi
                _list.Remove(existingNode);
                existingNode.Value = (key, image);
                _list.AddFirst(existingNode);
                return;
            }

            // Afegir nou
            var node = _list.AddFirst((key, image));
            _map[key] = node;

            // Descartar si s'excedeix la mida
            while (_list.Count > _maxSize)
            {
                var last = _list.Last!;
                _map.Remove(last.Value.Key);
                _list.RemoveLast();
            }
        }
    }

    /// <summary>
    /// Comprova si una clau existeix a la cache.
    /// </summary>
    public bool Contains(string key)
    {
        lock (_lock) return _map.ContainsKey(key);
    }

    /// <summary>
    /// Neteja tota la cache.
    /// </summary>
    public void Clear()
    {
        lock (_lock)
        {
            _list.Clear();
            _map.Clear();
        }
    }
}
