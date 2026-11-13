use crate::Error;

#[derive(Clone, Copy)]
pub(crate) struct Point {
    pub x: u16,
    pub y: u16,
}

pub(crate) struct Reader<'a> {
    bytes: &'a [u8],
    position: usize,
    section: &'static str,
}

impl<'a> Reader<'a> {
    pub(crate) const fn new(bytes: &'a [u8], section: &'static str) -> Self {
        Self {
            bytes,
            position: 0,
            section,
        }
    }

    pub(crate) const fn is_done(&self) -> bool {
        self.position == self.bytes.len()
    }

    pub(crate) fn byte(&mut self) -> crate::Result<u8> {
        let value = *self
            .bytes
            .get(self.position)
            .ok_or(self.invalid("truncated"))?;
        self.position += 1;
        Ok(value)
    }

    pub(crate) fn u16(&mut self) -> crate::Result<u16> {
        let value =
            crate::binary::u16_at(self.bytes, self.position).ok_or(self.invalid("truncated"))?;
        self.position += 2;
        Ok(value)
    }

    pub(crate) fn take(&mut self, count: usize) -> crate::Result<&'a [u8]> {
        let end = self
            .position
            .checked_add(count)
            .ok_or(self.invalid("truncated"))?;
        let bytes = self
            .bytes
            .get(self.position..end)
            .ok_or(self.invalid("truncated"))?;
        self.position = end;
        Ok(bytes)
    }

    pub(crate) fn ring_contains(&mut self, point: Point) -> crate::Result<bool> {
        let count = usize::from(self.u16()?);
        if count == 0 {
            return Ok(false);
        }
        let ring = self.take(
            count
                .checked_mul(4)
                .ok_or(self.invalid("ring size overflow"))?,
        )?;
        let mut winding = 0_i32;
        let mut previous = point_at(ring, count - 1);
        for index in 0..count {
            let current = point_at(ring, index);
            if previous.y <= point.y {
                if current.y > point.y && is_left(previous, current, point) > 0 {
                    winding += 1;
                }
            } else if current.y <= point.y && is_left(previous, current, point) < 0 {
                winding -= 1;
            }
            previous = current;
        }
        Ok(winding != 0)
    }

    fn invalid(&self, reason: &'static str) -> Error {
        Error::invalid(self.section, reason)
    }
}

fn point_at(ring: &[u8], index: usize) -> Point {
    let offset = index * 4;
    Point {
        x: u16::from_le_bytes([ring[offset], ring[offset + 1]]),
        y: u16::from_le_bytes([ring[offset + 2], ring[offset + 3]]),
    }
}

fn is_left(start: Point, end: Point, point: Point) -> i64 {
    (i64::from(end.x) - i64::from(start.x)) * (i64::from(point.y) - i64::from(start.y))
        - (i64::from(point.x) - i64::from(start.x)) * (i64::from(end.y) - i64::from(start.y))
}
