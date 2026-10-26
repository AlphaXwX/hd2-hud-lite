"""Patch archive primitives adapted from the unpacked Lite build tooling."""
from pathlib import Path
import struct

MAGIC=0xF0000011

def resource_hash(name):
    data=name.encode('utf-8')
    mask,mix=(1<<64)-1,0xC6A4A7935BD1E995
    value=len(data)*mix & mask
    end=len(data)//8*8
    for (word,) in struct.iter_unpack('<Q',data[:end]):
        word=word*mix & mask
        word^=word>>47
        value=(value^(word*mix & mask))*mix & mask
    if data[end:]:value=(value^int.from_bytes(data[end:],'little'))*mix & mask
    value^=value>>47
    value=value*mix & mask
    value^=value>>47
    return value

def read(path):
    data=path.read_bytes()
    gpu=Path(str(path)+'.gpu_resources').read_bytes()
    stream=Path(str(path)+'.stream').read_bytes()
    magic,ntypes,count=struct.unpack_from('<III',data)
    assert magic==MAGIC
    types=[struct.unpack_from('<QQQII',data,72+32*i) for i in range(ntypes)]
    assert sum(t[2] for t in types)==count
    rows=[]
    for i in range(count):
        fid,tid,off,soff,goff,a,b,size,ssize,gsize,ha,hb,seq=struct.unpack_from('<7Q6I',data,72+32*ntypes+80*i)
        assert off+size<=len(data) and soff+ssize<=len(stream) and goff+gsize<=len(gpu)
        rows.append(dict(fid=fid,tid=tid,data=data[off:off+size],stream=stream[soff:soff+ssize],
                         gpu=gpu[goff:goff+gsize],ha=ha,hb=hb,seq=seq))
    return data[12:72],types,rows

def write(path,header,types,rows):
    order={t[1]:i for i,t in enumerate(types)}
    rows=sorted(rows,key=lambda r:order[r['tid']])
    counts={}
    for r in rows:counts[r['tid']]=counts.get(r['tid'],0)+1
    types=[(t[0],t[1],counts[t[1]],t[3],t[4]) for t in types if counts.get(t[1])]
    head=struct.pack('<III',MAGIC,len(types),len(rows))+header
    for t in types:head+=struct.pack('<QQQII',*t)
    cursor=len(head)+80*len(rows)
    body,gpu,table=bytearray(),bytearray(),bytearray()
    for i,r in enumerate(rows,1):
        assert not r['stream'],'stream relocation is not needed for the Lite input'
        pad=-cursor%16;body+=b'\0'*pad;cursor+=pad
        goff=0
        if r['gpu']:
            gpu+=b'\0'*(-len(gpu)%64);goff=len(gpu);gpu+=r['gpu']
        table+=struct.pack('<7Q6I',r['fid'],r['tid'],cursor,0,goff,0,0,len(r['data']),0,len(r['gpu']),r['ha'],r['hb'],i)
        body+=r['data'];cursor+=len(r['data'])
    output=head+table+body
    output+=b'\0'*(-len(output)%16)
    path.write_bytes(output)
    Path(str(path)+'.gpu_resources').write_bytes(gpu)
    Path(str(path)+'.stream').write_bytes(b'')
